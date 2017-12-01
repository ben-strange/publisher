module Formats
  class ServiceSignInPresenter
    attr_reader :content

    def initialize(content)
      @content = content
    end

    def render_for_publishing_api
      {
        schema_name: "service_sign_in",
        rendering_app: "government-frontend",
        publishing_app: "publisher",
        document_type: "service_sign_in",
        locale: locale,
        update_type: update_type,
        change_note: change_note,
        base_path: base_path,
        routes: routes,
        title: title,
        description: description,
        public_updated_at: public_updated_at,
        content_id: content_id,
      }
    end

  private

    def locale
      content[:locale]
    end

    def update_type
      content[:update_type]
    end

    def change_note
      content[:change_note]
    end

    def base_path
      "/#{parent_slug}/sign-in"
    end

    def routes
      [
        { path: base_path.to_s, type: "prefix" },
      ]
    end

    def title
      parent.title
    end

    def description
      parent.overview
    end

    def public_updated_at
      return DateTime.now.rfc3339 if update_type == "major"

      content_item = Services.content_store.content_item(base_path)
      content_item["public_updated_at"]
    end

    def content_id
      SecureRandom.uuid
    end

    def parent
      @parent ||= Edition.where(slug: parent_slug).last
    end

    def parent_slug
      content[:start_page_slug]
    end
  end
end
