# EcoBuy auto-scaling demo (Azure)
Run everything in Azure Cloud Shell (Bash). Upload and unzip this folder first.
1. `python3 generate_data.py` -> traffic.csv, metrics.json (already included)
2. `terraform init`
3. `terraform apply -var alert_email=you@example.com -var admin_password='Str0ng!Passw0rd#1'`
   (if Standard_B1s is unavailable, change `sku` and/or `-var location=...`)
4. Open the `app_url` output; wait ~5 min for instances to become healthy
5. `python3 loadtest.py <app_url>` (about 25 min) and watch Monitor > Metrics
6. `terraform destroy` when done
