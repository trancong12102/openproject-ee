# frozen_string_literal: true

# ---------------------------------------------------------------------------
# Force-unlock all OpenProject Enterprise features.
#
# OpenProject — including its Enterprise add-ons — is licensed under GPLv3, which
# grants the right to run modified versions. This initializer overrides the
# runtime feature gates only. It does NOT forge or validate any license token:
# the closed-source `openproject-token` gem is bypassed entirely, because every
# caller funnels through the class methods overridden below.
#
# Pinned to the EE feature set of OpenProject 17.4.0.
# RE-VERIFY ON EVERY UPGRADE — method names and the feature list can change:
#   - gates:   app/models/enterprise_token.rb            (all class methods)
#   - labels:  config/locales/en.yml -> en.ee.features
#   - formats: config/initializers/custom_field_format.rb (enterprise_feature:)
# ---------------------------------------------------------------------------

module ForceEnterprise
  # Complete EE feature set as of OpenProject 17.4.0 (31 features).
  ALL_FEATURES = Set.new(%i[
    baseline_comparison
    board_view
    calculated_values
    capture_external_links
    custom_actions
    custom_field_hierarchies
    customize_life_cycle
    date_alerts
    define_custom_style
    edit_attribute_groups
    gantt_pdf_export
    internal_comments
    ldap_groups
    mcp_server
    meeting_templates
    nextcloud_sso
    one_drive_sharepoint_file_storage
    placeholder_users
    portfolio_management
    project_creation_wizard
    project_list_sharing
    readonly_work_packages
    scim_api
    sso_auth_providers
    team_planner_view
    time_entry_time_restrictions
    virus_scanning
    weighted_item_lists
    work_package_query_relation_columns
    work_package_sharing
    work_package_subject_generation
  ]).freeze

  # Every backend gate funnels through allows_to?. The Angular frontend reads
  # available_features / trialling_features from GET /api/v3/configuration to
  # decide which UI to show and whether to render upsell banners.
  def allows_to?(_feature)
    true
  end

  def active?
    true
  end

  def available_features
    ALL_FEATURES
  end

  def trialling_features
    Set.new # nothing flagged as "trial only"
  end

  def hide_banners?
    true # suppress EE upsell banners
  end

  def user_limit
    nil # nil disables the active-user / seat cap
  end
end

# to_prepare runs after eager-load (once in production), so EnterpriseToken is
# defined. The guard keeps it idempotent across code reloads in development.
Rails.application.config.to_prepare do
  unless EnterpriseToken.singleton_class.include?(ForceEnterprise)
    EnterpriseToken.singleton_class.prepend(ForceEnterprise)
  end
end
