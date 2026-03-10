class ApiDocsController < AdminController
  layout false

  def index; end

  def spec
    render file: Rails.root.join("swagger/v1/openapi.yaml"), content_type: "application/yaml"
  end
end
