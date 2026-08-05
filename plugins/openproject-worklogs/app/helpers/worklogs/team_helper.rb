module Worklogs
  module TeamHelper
    # The team sheet is its URL, like every other page here: each control is
    # this hash with one thing changed, which is what keeps the filters alive
    # across a step, an expansion and a week/month switch alike.
    def worklogs_team_params(query, overrides = {})
      query.to_params.merge(overrides.symbolize_keys).compact
    end

    def worklogs_team_href(query, overrides = {})
      worklogs_team_path(worklogs_team_params(query, overrides))
    end

    # Each dropdown is its own GET form and has to carry the rest of the page
    # with it, or applying one filter would clear every other.
    def worklogs_team_hidden_fields(query, except: [])
      excluded = Array(except).map(&:to_sym)

      safe_join(worklogs_team_params(query).except(*excluded).flat_map do |name, value|
        Array(value).map do |single|
          hidden_field_tag("#{name}#{'[]' if value.is_a?(Array)}", single, id: nil)
        end
      end)
    end
  end
end
