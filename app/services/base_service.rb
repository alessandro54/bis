# app/services/base_service.rb
class BaseService
  def self.call(*args, **kwargs, &block)
    new(*args, **kwargs).call(&block)
  end

  private

    def success(payload = nil, message: nil, context: {})
      ServiceResult.success(payload, message: message, context: context)
    end

    def failure(error, message: nil, payload: nil, context: {}, captured: false)
      if error.is_a?(Exception) && !captured
        Sentry.capture_exception(error, extra: { service: self.class.name }.merge(context))
      end
      ServiceResult.failure(error, message: message, payload: payload, context: context)
    end
end
