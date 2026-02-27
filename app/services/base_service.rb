# app/services/base_service.rb
class BaseService
  def self.call(*args, **kwargs, &block)
    new(*args, **kwargs).call(&block)
  end

  private

    def success(payload = nil, message: nil, context: {})
      ServiceResult.success(payload, message: message, context: context)
    end

    def failure(error, message: nil, payload: nil, context: {})
      ServiceResult.failure(error, message: message, payload: payload, context: context)
    end
end
