import Config

secret = System.get_env("VERCEL_WEBHOOK_SECRET")
flush_seconds = System.get_env("LOG_FLUSH_INTERVAL") || "5"

s3_bucket = System.get_env("S3_BUCKET")
s3_region = System.get_env("S3_REGION", "us-east-1")
s3_endpoint = System.get_env("S3_ENDPOINT")
s3_access_key = System.get_env("AWS_ACCESS_KEY_ID")
s3_secret_key = System.get_env("AWS_SECRET_ACCESS_KEY")

if secret in [nil, ""] && config_env() == :prod do
  raise "VERCEL_WEBHOOK_SECRET must be set in production"
end

config :ex_logdrain,
  vercel_webhook_secret: secret,
  flush_interval: String.to_integer(flush_seconds),
  s3_bucket: s3_bucket,
  s3_region: s3_region,
  s3_endpoint: s3_endpoint,
  s3_access_key_id: s3_access_key,
  s3_secret_access_key: s3_secret_key
