# Gatus は CORS ヘッダを出さない (dev 時の localhost だけ) ので、
# GitHub Pages のフロントが API を読めるよう Cloudflare でレスポンスに付ける
resource "cloudflare_ruleset" "status_cors" {
  zone_id = var.zone_id
  name    = "status-api CORS"
  kind    = "zone"
  phase   = "http_response_headers_transform"

  rules = [
    {
      ref         = "status_api_cors"
      description = "status.riya.work から status-api を読めるようにする"
      expression  = "(http.host eq \"${local.status_api_hostname}\")"
      action      = "rewrite"
      action_parameters = {
        headers = {
          "Access-Control-Allow-Origin" = {
            operation = "set"
            value     = "https://${local.status_hostname}"
          }
        }
      }
    },
  ]
}
