# S3 buckets

Two buckets per environment:

| Bucket | Name | Who reads it | For |
|---|---|---|---|
| **Private** | `<project>-<env>-private-<account-id>` | Only IAM roles/users you grant | Logs, backups, uploads, anything internal |
| **Public** | `<project>-<env>-public-<account-id>` | The internet, **only through CloudFront** | Static assets: js, css, images, fonts, media |

Bucket names are global across every AWS account, so the account ID is added to
avoid clashing with somebody else's bucket.

## Private bucket

Organise it with key prefixes. S3 has no real folders: a prefix exists as soon as a
file is uploaded under it. `backups/`, `backups/kubernetes/`, `backups/postgres/` and `backups/redis/` are
created as empty "folder" objects (like the S3 console's "Create folder") so the layout
is visible before the first backup.

| Prefix | Kept for | Written by |
|---|---|---|
| `logs/` | 30 days (`log_retention_days`) | e.g. `logs/nginx/2026-11-05.gz` |
| `backups/kubernetes/` | 30 days (`backup_retention_days`) | etcd nodes, every 6 h: `backups/kubernetes/etcd/etcd-1/etcd-1-<time>.db.gz` |
| `backups/postgres/` | **Managed by pgBackRest** (4 weekly fulls + WAL) | PostgreSQL primary |
| `backups/redis/` | 30 days (`backup_retention_days`) | Redis master, daily: `backups/redis/redis-<time>.rdb.gz` |
| `backups/elasticsearch/` | **Managed by Elasticsearch** (snapshot policy: 30 days) | Elasticsearch nodes, daily snapshot repository `s3-backups` |
| `backups/mongodb/` | 30 days | daily snapshot repository `s3-backups` |
| `tmp/` | 7 days | Scratch files |
| `web/` | Until deleted | The web team's own files and backups |
| anything else | Until deleted | `uploads/`, ... |

- **Versioning is on.** Overwritten or deleted files can be restored for 30 days
  (`noncurrent_version_retention_days`). So `logs/` really disappears after 30 + 30 days.
- **Use `/` in keys, not `\`.** `backups/kubernetes/`, never `Production\Kubernetes`.
  Use one bucket per environment instead of an environment folder.
- **Never add an age-based lifecycle rule for `backups/postgres/` or `backups/elasticsearch/`.**
  Elasticsearch snapshots are incremental and share files, and so do pgBackRest backups. pgBackRest decides which
  files are still needed: an old full backup that newer differentials build on, and the WAL
  between them. Deleting them by age leaves backups that can't be restored. Retention is
  `backup_retention_full` in `postgres-cluster`, and the snapshot policy in `elasticsearch-cluster`.
- **Each writer can only reach its own prefix.** The etcd nodes can only upload to
  `backups/kubernetes/etcd/` (no read or delete). The PostgreSQL nodes can only use
  `backups/postgres/`. Versioning keeps deleted files for 30 days in case something goes wrong.

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
