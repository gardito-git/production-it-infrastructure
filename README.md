# AWS Production IT Infrastructure
TO-DO
1. VPC (With VPN)
2. Kubernetes Cluster on EC2 (kubeadm + external etcd)
3. PostgreSQL cluster on EC2 (Patroni)
4. Web Server Nginx on EC2 behind CloudFront and an internal Application Load Balancer
5. NextJS on EC2 (PM2) behind the Nginx web servers, with S3 and CloudFront
6. Redis Sentinel on EC2
7. RabbitMQ cluster on EC2 (3 nodes, quorum queues)
8. GitHub Actions self-hosted runners on EC2 (3 runners)
9. Harbor private container registry on EC2 with S3 storage
10. MongoDB replica set on EC2 (3 members)
