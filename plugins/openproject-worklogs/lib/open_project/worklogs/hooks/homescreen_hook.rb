module OpenProject
  module Worklogs
    module Hooks
      # Puts the week's state on the OpenProject home page.
      #
      # `homescreen_after_links` is the only server-rendered hook on that page,
      # which suits a plugin that cannot touch the Angular bundle. The component
      # decides for itself whether to render, so a user without `view_worklogs`
      # sees the homescreen exactly as it was.
      class HomescreenHook < ::OpenProject::Hook::ViewListener
        def homescreen_after_links(context = {})
          context[:hook_caller].render(::Worklogs::Homescreen::BlockComponent.new)
        end

        # The plugin's stylesheet is linked per page rather than globally, so
        # the one page it is borrowed on has to ask for it — and only when there
        # is actually a block to style.
        def view_layouts_base_html_head(context = {})
          return "" unless homescreen?(context) && ::Worklogs::Homescreen::BlockComponent.new.render?

          context[:hook_caller].tag.link(rel: "stylesheet", href: Assets.path("worklogs.css"))
        end

        private

        def homescreen?(context)
          context[:controller].is_a?(::HomescreenController)
        end
      end
    end
  end
end
