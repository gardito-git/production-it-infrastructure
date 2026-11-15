# Percona Monitoring and Management with Grafana Dashboard

Self-hosted PMM with Grafana Dashboard if you want stay away from AWS Cloudwatch. This is good considering we have self-hosted databases cluster, in this project we use:
- PostgreSQL (https://docs.percona.com/percona-monitoring-and-management/3/install-pmm/install-pmm-client/connect-database/postgresql.html), 
- MongoDB (https://docs.percona.com/percona-monitoring-and-management/3/install-pmm/install-pmm-client/connect-database/mongodb.html) and 
- Redis (https://docs.percona.com/percona-monitoring-and-management/3/install-pmm/install-pmm-client/connect-database/valkey-redis.html). 

Because all of our system under Ubuntu 24.04, we can add Linux monitoring (https://docs.percona.com/percona-monitoring-and-management/3/install-pmm/install-pmm-client/connect-database/linux.html).

And we don't discuss ELK Stack (Monitoring with Kibana and all those Metricbeat, Filebeat, etc), because it's not free.
## Setup 
- Dedicated Grafana Dashboard instance with `r8i.xlarge` with dedicated 100GB EBS GP3 type
  - Dedicated `loki-promtail` and `prometheus` instance `m8i.xlarge` under docker and installed `EFS Server` (Because AWS EFS is expensive).
    Mounting every EC2 instance (with installed `EFS Client`) for their logs and metrics:
    - Dedicated 100GB EBS GP3 type for logs folder `/mnt/prod/logs`. Set logrotate 30 days.
      - `/mnt/prod/logs/nextjs`
      - `/mnt/prod/logs/nginx`
      - `/mnt/prod/logs/kubernetes`
      - `/mnt/prod/logs/postgres`
      - `/mnt/prod/logs/rabbitmq`
      - `/mnt/prod/logs/redis`
      - `/mnt/prod/logs/elastic`

      (Optional)
      - `/mnt/prod/logs/vpn`
      - `/mnt/prod/logs/harbor`
      - `/mnt/prod/logs/github-runner`
      - `/mnt/prod/logs/mongodb`
    - Dedicated 100GB EBS GP3 type for metrics folder `/mnt/prod/prometheus`. Set logrotate 30 days.
      - `/mnt/prod/prometheus/nextjs`
      - `/mnt/prod/prometheus/nginx`
      - `/mnt/prod/prometheus/kubernetes`
      - `/mnt/prod/prometheus/postgres`
      - `/mnt/prod/prometheus/rabbitmq`
      - `/mnt/prod/prometheus/redis`
      - `/mnt/prod/prometheus/elastic`

      (Optional)
      - `/mnt/prod/prometheus/vpn`
      - `/mnt/prod/prometheus/harbor`
      - `/mnt/prod/prometheus/github-runner`
      - `/mnt/prod/prometheus/mongodb`
- Setup metric time intervals and resolutions are 5 seconds (based on my experience, under 5 seconds always troublesome, so use for your own risk)
- Login with Github-SSO based on Organization. If you want create 1 by 1 user for all your engineer or just create based on department, such as `engineer`, `manager`, `monitoring`, basically all with `view-only` roles but keep `admin` for your self. (https://docs.percona.com/percona-monitoring-and-management/3/admin/manage-users/index.html)
- For alerting, the most common work-communication apps is Slack, so you must create Alert manually when Grafana Dashboard already up.
(https://grafana.com/docs/grafana/latest/alerting/configure-notifications/manage-contact-points/)
- Grafana Dashboard can only accessible by vpn with internal IP or with local url, for example: `monitoring.example.local` 