import Config

secret = System.get_env("VERCEL_WEBHOOK_SECRET")
flush_seconds = System.get_env("LOG_FLUSH_INTERVAL") || "5"

if secret in [nil, ""] && config_env() == :prod do
  raise "VERCEL_WEBHOOK_SECRET must be set in production"
end

config :ex_logdrain,
  vercel_webhook_secret: secret || "test_secret",
  flush_interval: String.to_integer(flush_seconds)
