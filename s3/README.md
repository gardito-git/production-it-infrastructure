# S3 buckets

Two buckets per environment:

| Bucket | Name | Who reads it | For |
|---|---|---|---|
| **Private** | `<project>-<env>-private-<account-id>` | Only IAM roles/users you grant | Logs, backups, uploads, anything internal |
| **Public** | `<project>-<env>-public-<account-id>` | The internet, **only through CloudFront** | Static assets: js, css, images, fonts, media |

Bucket names are global across every AWS account, so the account ID is added to
avoid clashing with somebody else's bucket.

## Private bucket

Organise it with key prefixes. S3 has no real folders: `backups/kubernetes/etcd/`
exists as soon as you upload a file to it, so nothing needs creating in advance.

| Prefix | Kept for | Example |
|---|---|---|
| `logs/` | 30 days (`log_retention_days`) | `logs/nginx/2026-11-05.gz` |
| `backups/` | 30 days (`backup_retention_days`) | `backups/kubernetes/etcd/snapshot-2026-11-05.db` |
| `tmp/` | 7 days | Scratch files |
| `web/` | Until deleted | The web team's own files and backups |
| anything else | Until deleted | `uploads/`, ... |

- **Versioning is on.** Overwritten or deleted files can be restored for 30 days
  (`noncurrent_version_retention_days`). So `logs/` really disappears after 30 + 30 days.
- **Use `/` in keys, not `\`.** `backups/kubernetes/`, never `Production\Kubernetes`.
  Use one bucket per environment instead of an environment folder.
- **PostgreSQL backups are not here.** pgBackRest has its own bucket
  (`postgres-cluster/backups.tf`), keeps them for 4 weeks itself, and only the database
  nodes can write to it. Keeping critical backups in a separate bucket limits who and
  what can delete them.

## Public bucket + CloudFront

```
browser ──HTTPS──► CloudFront (edge cache) ──signed request──► S3 bucket (private)
```

The bucket is **not public**. CloudFront reads it through Origin Access Control, and the
bucket policy allows only this distribution. You get HTTPS, compression, HTTP/3,
security headers, and caching near your users. Data transfer is cheaper than serving
from S3 directly (the first 1 TB/month out of CloudFront is free).

Deploy from CI or a laptop (needs the `web-developers` group):

```bash
BUCKET=$(terraform output -raw public_bucket_name)
DIST=$(terraform output -raw public_cdn_distribution_id)

aws s3 sync ./dist "s3://$BUCKET/" --delete
aws cloudfront create-invalidation --distribution-id "$DIST" --paths "/index.html"
```

**Use content-hashed file names** (`app.3f9a1c.js`, which Vite and webpack do by default).
They can be cached forever, and you only invalidate files whose names don't change,
like `index.html`. Invalidating `/*` on every deploy works but empties the whole cache.

Files are at `https://<public_cdn_domain>/<key>`, e.g. `/images/logo.svg`.

## Web team access

Add people to the IAM group from the `web_developers_group` output. They can:

- upload, overwrite and delete anything in the **public** bucket, and invalidate the CloudFront cache;
- read and write `web/` in the **private** bucket, for their own backups.

They can't see or touch anything else in the private bucket.

## Outputs

| Name | Description |
|---|---|
| `private_bucket_name`, `private_bucket_arn` | Private bucket |
| `public_bucket_name` | Public bucket |
| `public_cdn_domain` | `xxxx.cloudfront.net` |
| `public_cdn_distribution_id` | For invalidations |
| `web_developers_group` | IAM group for the web team |

## TO-DO

- [ ] Custom domain (e.g. `assets.example.com`): ACM certificate in **us-east-1** + `aliases` on the distribution + DNS record
- [ ] CORS response headers, if fonts or assets are loaded from another domain
- [ ] S3 Object Lock on `backups/` (a separate bucket) so backups can't be deleted even by an admin, against ransomware
- [ ] Access logging (S3 server access logs or CloudFront logs) into `logs/`
