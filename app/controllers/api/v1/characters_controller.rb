class Api::V1::CharactersController < Api::V1::BaseController
  def index
    characters = Character.first(10)

    render json: characters
  end
end
