module Worklogs
  class AssetsController < ApplicationController
    skip_before_action :check_if_login_required, raise: false
    skip_before_action :verify_authenticity_token, raise: false

    no_authorization_required! :show

    def show
      file = OpenProject::Worklogs::Assets.file_path(params[:filename])
      return head(:not_found) if file.nil?

      # The URL carries a content digest, so a hit can never be stale.
      expires_in 1.year, public: true
      response.headers["Cache-Control"] = "public, max-age=31536000, immutable"

      send_file file,
                type: OpenProject::Worklogs::Assets.content_type(params[:filename]),
                disposition: "inline"
    end
  end
end
