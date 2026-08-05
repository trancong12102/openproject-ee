module Worklogs
  class AssetsController < ApplicationController
    skip_before_action :check_if_login_required, raise: false
    skip_before_action :verify_authenticity_token, raise: false

    no_authorization_required! :show

    def show
      file = OpenProject::Worklogs::Assets.file_path(params[:filename])
      return head(:not_found) if file.nil?

      # The digest has to be checked, not merely carried. Answering an old digest
      # with the current file — under a header that promises the answer will
      # never change — is how a proxy ends up holding today's CSS against
      # yesterday's URL for a year. A miss is a 404, and the page that asked has
      # already been re-rendered with the new digest.
      return head(:not_found) unless params[:digest] == OpenProject::Worklogs::Assets
                                                        .digest(params[:filename])

      expires_in 1.year, public: true
      response.headers["Cache-Control"] = "public, max-age=31536000, immutable"

      send_file file,
                type: OpenProject::Worklogs::Assets.content_type(params[:filename]),
                disposition: "inline"
    end
  end
end
