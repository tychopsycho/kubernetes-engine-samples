
#1. Create a service account to run the pipeline
gcloud iam service-accounts create mql-export-metrics \
--display-name "MQL export metrics SA" \
--description "Used for the function that export monitoring metrics"

#1. Assigning IAM roles to the service account
gcloud projects add-iam-policy-binding  $PROJECT_ID --member="serviceAccount:mql-export-metrics@$PROJECT_ID.iam.gserviceaccount.com" --role="roles/monitoring.viewer"
gcloud projects add-iam-policy-binding  $PROJECT_ID --member="serviceAccount:mql-export-metrics@$PROJECT_ID.iam.gserviceaccount.com" --role="roles/bigquery.dataEditor"
gcloud projects add-iam-policy-binding  $PROJECT_ID --member="serviceAccount:mql-export-metrics@$PROJECT_ID.iam.gserviceaccount.com" --role="roles/bigquery.dataOwner"
gcloud projects add-iam-policy-binding  $PROJECT_ID --member="serviceAccount:mql-export-metrics@$PROJECT_ID.iam.gserviceaccount.com" --role="roles/bigquery.jobUser"
gcloud projects add-iam-policy-binding  $PROJECT_ID --member="serviceAccount:mql-export-metrics@$PROJECT_ID.iam.gserviceaccount.com" --role="roles/run.invoker"


#1. Deploy the Cloud Run Job
gcloud beta run jobs deploy metric-exporter \
    --image=us-docker.pkg.dev/google-samples/containers/gke/metrics-exporter:latest \
    --set-env-vars=PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION=python \
    --set-env-vars=PROJECT_ID=$PROJECT_ID \
    --execute-now \
    --memory=1Gi \
    --max-retries=1 \
    --parallelism=0 \
    --service-account=mql-export-metrics@$PROJECT_ID.iam.gserviceaccount.com \
    --region=$REGION

#1. Create a schedule to run once a day
gcloud scheduler jobs create http metric-exporter \
  --location $REGION \
  --schedule="0 23 * * *" \
  --uri="https://$REGION-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/$PROJECT_ID/jobs/metric-exporter:run" \
  --http-method POST \
  --oauth-service-account-email "mql-export-metrics@$PROJECT_ID.iam.gserviceaccount.com"
