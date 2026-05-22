import Config

vercel_secret = System.get_env("VERCEL_WEBHOOK_SECRET") || "test_secret"
flush_seconds = System.get_env("LOG_FLUSH_INTERVAL") || "5"

config :ex_logdrain,
  vercel_webhook_secret: vercel_secret,
  flush_interval: String.to_integer(flush_seconds)
