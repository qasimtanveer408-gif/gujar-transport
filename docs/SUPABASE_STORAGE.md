# Private documents

Buckets: gbt-vehicles, gbt-drivers, gbt-trips, gbt-maintenance and gbt-office-expenses. Each is private with a 10 MB limit for JPEG, PNG and PDF. Driver documents require a separate sensitive-data capability.

Uploads reserve a generated metadata/path, validate file extension/MIME/signature on Express, upload using the caller's Storage client and finalize only if the object exists. Downloads recheck row access before a 60-second signed attachment link. Previously issued links remain valid until their short expiry. No durable upload is placed on Hostinger disk.

PDF screening rejects common active constructs but is not a complete malware scanner. Deletion marks metadata, removes bytes via Storage API, then finalizes. Failed uploads remain pending for reviewed cleanup. Automatic orphan-cleanup scheduling is not enabled in this checkpoint; a safe claim/cleanup workflow remains an explicit follow-up before automating deletion.

Back up metadata and document bytes separately. Test real upload/download/delete, out-of-scope denial, signed-link expiry, failed-upload recovery and restart persistence in staging; none were externally verified here.
