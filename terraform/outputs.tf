output "host_tunnel_tokens" {
  value     = module.cloudflare.host_tunnel_tokens
  sensitive = true
}

output "host_ops_service_token_client_id" {
  value     = module.cloudflare.host_ops_service_token_client_id
  sensitive = true
}

output "host_ops_service_token_client_secret" {
  value     = module.cloudflare.host_ops_service_token_client_secret
  sensitive = true
}
