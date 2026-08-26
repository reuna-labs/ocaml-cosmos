module Chain_id = Cosmos_types.Chain_id
module Intent = Cosmos_tx.Intent
module Policy = Cosmos_tx.Policy

type sign_mode = Direct | Legacy_amino_json

let sign_mode_to_string = function
  | Direct -> "SIGN_MODE_DIRECT"
  | Legacy_amino_json -> "SIGN_MODE_LEGACY_AMINO_JSON"

let sign_mode_byte = function Direct -> 1 | Legacy_amino_json -> 2

(* Domain separators. Distinct so that a request digest can never be mistaken
   for an approval digest, however the two are stored or passed around. *)
let request_domain = "reuna.cosmos.signer.request.v1"
let approval_domain = "reuna.cosmos.signer.approval.v1"

type request = {
  chain_id : Chain_id.t;
  account_number : int64;
  sequence : int64;
  sign_mode : sign_mode;
  payload : string;
  nonce : string;
  not_after : int64;
}

let request ~chain_id ~account_number ~sequence ~sign_mode ~payload ~nonce
    ~not_after =
  if payload = "" then Error "transcript: the payload is empty"
  else if String.length nonce < 16 then
    (* Short enough to collide is short enough to replay. Sixteen bytes is the
       smallest that is not an invitation; the caller chooses how it is
       generated, since this library draws no randomness. *)
    Error "transcript: the nonce must be at least 16 bytes"
  else if not_after <= 0L then
    Error
      "transcript: not_after must be set -- a signing request with no expiry \
       is one that can be held and used later"
  else
    Ok
      {
        chain_id;
        account_number;
        sequence;
        sign_mode;
        payload;
        nonce;
        not_after;
      }

let encode_request r =
  Canonical.create request_domain |> fun c ->
  Canonical.string c (Chain_id.to_string r.chain_id) |> fun c ->
  Canonical.int64 c r.account_number |> fun c ->
  Canonical.int64 c r.sequence |> fun c ->
  Canonical.byte c (sign_mode_byte r.sign_mode) |> fun c ->
  Canonical.string c r.payload |> fun c ->
  Canonical.string c r.nonce |> fun c -> Canonical.int64 c r.not_after

let request_digest r = Canonical.digest (encode_request r)

let check_freshness r ~now =
  if now > r.not_after then
    Error
      (Printf.sprintf "transcript: the request expired at %Ld and it is now %Ld"
         r.not_after now)
  else Ok ()

type review = {
  request : request;
  intent : Intent.t;
  rendering : string;
  (* What the signature will cover. The payload in Direct; the amino document
     derived from it in Legacy_amino_json. Derived, never supplied -- see the
     note on [request] in the .mli. *)
  signed_bytes : string;
}

let intent t = t.intent
let rendering t = t.rendering
let reviewed_request t = t.request
let signed_bytes t = t.signed_bytes

let review ~base ~policy r =
  (* The payload is a SignDoc in both modes, and is decoded rather than
     described. What differs is only what ends up being signed. *)
  match Cosmos_tx.Sign_doc.of_bytes r.payload with
  | Error e -> Error [ "transcript: " ^ e ]
  | Ok doc -> (
      (* The chain id and account number inside the payload must be the ones the
       request claims. A request naming one chain while carrying a document for
       another is exactly the substitution this catches, and it is cheap to
       check because both are present. *)
      let payload_chain = Cosmos_tx.Sign_doc.chain_id doc in
      let payload_account = Cosmos_tx.Sign_doc.account_number doc in
      if not (Chain_id.equal payload_chain r.chain_id) then
        Error
          [
            Printf.sprintf
              "transcript: the request names chain %s and the payload is for %s"
              (Chain_id.to_string r.chain_id)
              (Chain_id.to_string payload_chain);
          ]
      else if payload_account <> r.account_number then
        Error
          [
            Printf.sprintf
              "transcript: the request names account %Ld and the payload is \
               for %Ld"
              r.account_number payload_account;
          ]
      else
        match Intent.of_sign_doc ~base doc with
        | Error e -> Error [ "transcript: " ^ e ]
        | Ok intent -> (
            if intent.Intent.sequence <> r.sequence then
              Error
                [
                  Printf.sprintf
                    "transcript: the request names sequence %Ld and the \
                     payload is for %Ld"
                    r.sequence intent.Intent.sequence;
                ]
            else
              (* What will actually be signed. In amino mode this is computed here,
             from the same bytes that were just reviewed, so the two encodings
             cannot describe different transactions. *)
              let signed =
                match r.sign_mode with
                | Direct -> Ok r.payload
                | Legacy_amino_json -> (
                    match
                      ( Cosmos_tx.Body.of_bytes ~base
                          (Cosmos_tx.Sign_doc.body_bytes doc),
                        Cosmos_tx.Auth_info.of_bytes ~base
                          (Cosmos_tx.Sign_doc.auth_info_bytes doc) )
                    with
                    | Error e, _ | _, Error e -> Error e
                    | Ok body, Ok auth_info ->
                        Cosmos_tx.Amino_json.sign_bytes ~body ~auth_info
                          ~chain_id:payload_chain
                          ~account_number:payload_account)
              in
              match signed with
              | Error e -> Error [ "transcript: " ^ e ]
              | Ok signed_bytes -> (
                  match Policy.review policy intent with
                  | Policy.Refused reasons -> Error reasons
                  | Policy.Approved ->
                      let rendering = Format.asprintf "%a" Intent.pp intent in
                      Ok { request = r; intent; rendering; signed_bytes })))

type approval = {
  review : review;
  signature : Cosmos_crypto.signature;
  measurement : string;
}

let signature t = t.signature
let approved_review t = t.review
let sha256 s = Digestif.SHA256.(to_raw_string (digest_string s))
let payload_digest r = sha256 r.payload

(* What the signature covers. Equal to the payload digest in Direct; in amino
   mode it is the digest of the document derived from that payload, and the two
   differ. *)
let signed_digest a = sha256 a.review.signed_bytes

let sign rv ~key ~measurement =
  if measurement = "" then
    Error
      "transcript: a measurement is required -- an approval that cannot say \
       which code produced it is not evidence of anything"
  else
    match Cosmos_crypto.sign_digest ~key (sha256 rv.signed_bytes) with
    | Error _ as e -> e
    | Ok signature -> Ok { review = rv; signature; measurement }

let encode_approval a =
  Canonical.create approval_domain |> fun c ->
  Canonical.string c (request_digest a.review.request) |> fun c ->
  Canonical.string c a.review.rendering |> fun c ->
  Canonical.string c (Cosmos_crypto.signature_to_bytes a.signature) |> fun c ->
  Canonical.string c a.measurement

let approval_digest a = Canonical.digest (encode_approval a)

let verify a ~key ~now =
  let r = a.review.request in
  match check_freshness r ~now with
  | Error _ as e -> e
  | Ok () ->
      if not (Cosmos_crypto.verify_digest ~key a.signature (signed_digest a))
      then
        Error
          "transcript: the signature does not cover what the review approved"
      else
        (* The rendering has to be the one this payload produces. If it is not,
         the words in the record are not the words the bytes mean -- which is
         exactly the substitution the whole design is against, and is worth
         re-deriving rather than trusting. *)
        let expected = Format.asprintf "%a" Intent.pp a.review.intent in
        if expected <> a.review.rendering then
          Error "transcript: the rendering does not match the intent"
        else Ok ()

let pp ppf a =
  let r = a.review.request in
  let hex s =
    String.concat ""
      (List.map
         (fun c -> Printf.sprintf "%02x" (Char.code c))
         (List.init (String.length s) (String.get s)))
  in
  Format.fprintf ppf "@[<v>";
  Format.fprintf ppf "approval       %s@," (hex (approval_digest a));
  Format.fprintf ppf "request        %s@," (hex (request_digest r));
  Format.fprintf ppf "sign mode      %s@," (sign_mode_to_string r.sign_mode);
  Format.fprintf ppf "payload        %d bytes, sha256 %s@,"
    (String.length r.payload)
    (hex (payload_digest r));
  (* In amino mode the bytes signed are not the bytes reviewed -- they are a
     different encoding of them -- so the record says so rather than leaving a
     reader to assume they are the same. *)
  if signed_digest a <> payload_digest r then
    Format.fprintf ppf
      "signed         %d bytes, sha256 %s (a different encoding)@,"
      (String.length a.review.signed_bytes)
      (hex (signed_digest a));
  Format.fprintf ppf "nonce          %s@," (hex r.nonce);
  Format.fprintf ppf "not after      %Ld@," r.not_after;
  Format.fprintf ppf "measurement    %s@," a.measurement;
  Format.fprintf ppf "signature      %s@,"
    (hex (Cosmos_crypto.signature_to_bytes a.signature));
  Format.fprintf ppf "@,%s@," a.review.rendering;
  Format.fprintf ppf "@]"
