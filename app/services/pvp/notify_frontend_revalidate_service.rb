module Pvp
  class NotifyFrontendRevalidateService < BaseService
    def call
      url    = ENV["FRONTEND_URL"]
      secret = ENV["REVALIDATE_SECRET"]
      return success(nil) unless url.present? && secret.present?

      HTTPX.post("#{url}/api/revalidate", headers: { "x-revalidate-secret" => secret })
      Rails.logger.info("[NotifyFrontendRevalidateService] Frontend cache revalidated")
      success(nil)
    rescue => e
      Rails.logger.warn("[NotifyFrontendRevalidateService] Failed: #{e.message}")
      success(nil)
    end
  end
end
