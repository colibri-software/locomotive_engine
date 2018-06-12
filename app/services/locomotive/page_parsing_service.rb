require 'active_support/benchmarkable'

module Locomotive

  class PageParsingService < Struct.new(:site, :locale)

    include ActiveSupport::Benchmarkable

    def find_all_elements(page)
      find_or_create_editable_elements(page)&.slice(:elements, :sections)
    end

    def find_or_create_editable_elements(page)
      benchmark "Parse page #{page._id} find_or_create_editable_elements" do
        parsed = { extends: {}, blocks: {}, super_blocks: {}, elements: [], sections: [] }

        subscribe(parsed) do
          parse(page)

          # Warning, this method also modifies the parsed[:elements] array by
          # removing non visible editable elements.
          persist_editable_elements!(page, parsed)
        end

        parsed
      end
    rescue Exception => e
      logger.error "[PageParsing] " + e.message + "\n\t" + e.backtrace.join("\n\t")
      nil
    end

    # Each element of the elements parameter is a couple: Page, EditableElement
    def group_and_sort_editable_elements(elements)
      elements.group_by { |(_, el)| el.block }.tap do |groups|
        groups.each do |_, list|
          list.sort! { |(_, a), (_, b)| (b.priority || 0) <=> (a.priority || 0) }
        end
      end
    end

    def blocks_from_grouped_editable_elements(groups)
      groups.map do |block, elements|
        next if elements.empty?

        element = elements.first.last

        { name: block, label: element.block_label, priority: element.block_priority || 0 }
      end.compact.sort { |a, b| b[:priority] <=> a[:priority] }
    end

    private

    def subscribe(parsed, &block)
      subscribers = [
        subscribe_to_extends(parsed[:extends]),
        subscribe_to_blocks(parsed[:blocks], parsed[:super_blocks]),
        subscribe_to_editable_elements(parsed[:elements]),
        subscribe_to_sections(parsed[:sections]),
        subscribe_to_sections_dropzones(parsed[:sections])
      ]

      yield.tap do
        subscribers.each do |subscriber|
          ActiveSupport::Notifications.unsubscribe(subscriber)
        end
      end
    end

    def subscribe_to_extends(extends)
      ActiveSupport::Notifications.subscribe('steam.parse.extends') do |name, start, finish, id, payload|
        parent_id, page_id = payload[:parent]._id, payload[:page]._id
        extends[parent_id] = page_id
      end
    end

    def subscribe_to_blocks(blocks, super_blocks)
      ActiveSupport::Notifications.subscribe('steam.parse.inherited_block') do |name, start, finish, id, payload|
        page_id, block_name, found_super = payload[:page]._id, payload[:name], payload[:found_super]
        super_blocks[page_id] ||= {}
        super_blocks[page_id][block_name] = found_super

        blocks[block_name] ||= payload.slice(:short_name, :priority)
      end
    end

    def subscribe_to_editable_elements(elements)
      ActiveSupport::Notifications.subscribe(/\Asteam\.parse\.editable\./) do |name, start, finish, id, payload|
        page, attributes = payload[:page], payload[:attributes]
        elements << [page, attributes]
      end
    end

    def subscribe_to_sections(sections)
      ActiveSupport::Notifications.subscribe('steam.parse.section') do |name, start, finish, id, payload|
        sections.push(payload[:name])
      end
    end

    def subscribe_to_sections_dropzones(sections)
      ActiveSupport::Notifications.subscribe('steam.parse.sections_dropzone') do |name, start, finish, id, payload|
        sections.push('_sections_dropzone_')
      end
    end

    def parse(page)
      entity = repository.build(page.attributes.dup)
      decorated_page = Locomotive::Steam::Decorators::TemplateDecorator.new(entity, self.locale, self.site.default_locale)

      parser = services.liquid_parser
      parser.parse(decorated_page)
    end

    def persist_editable_elements!(page, parsed)
      modified_pages, pages = [], { page._id => page } # group modifications by page

      parsed[:elements].map! do |couple|
        _page, attributes = couple

        next if !persist_editable_element?(page, parsed, _page, attributes)

        # Note: _page is a Steam entity but we need a Mongoid document to save the elements
        _page = attributes[:fixed] ? find_page(_page._id, pages) : page

        element = add_or_modify_editable_element(_page, attributes)
        couple[0], couple[1] = _page, element # we get now a Mongoid document instead of a Steam entity

        assign_block_information(element, parsed[:blocks])

        modified_pages << _page

        couple
      end.compact!

      modified_pages.uniq.map(&:save!)
    end

    def persist_editable_element?(page, parsed, _page, attributes)
      page_id, block_name = _page._id, attributes[:block]

      if page._id == _page._id  # same page
        true
      elsif block_name.blank?   # an editable_element out of a block (impossible to remove it in pages extending this template)
        true
      else
        block_visible?(_page._id, parsed, attributes)
      end
    end

    def block_visible?(page_id, parsed, attributes)
      block_name = attributes[:block]
      descendant = parsed[:extends][page_id]

      return true if descendant.nil?

      # find if the descendant hides the block
      if (blocks = parsed[:super_blocks][descendant]).blank?
        # we can not know for sure, ask the descendant of the descendant
        block_visible?(descendant, parsed, attributes)
      else
        found_super = blocks[block_name]
        hidden = blocks.keys.any? { |name| block_name =~ /\A#{name}(\Z|\/)/ }
        if found_super || !hidden
          # again, we need to ask the descendant of the descendant
          block_visible?(descendant, parsed, attributes)
        end
      end
    end

    def add_or_modify_editable_element(page, attributes)
      if element = page.editable_elements.by_block_and_slug(attributes[:block], attributes[:slug]).first
        # context: the editable element has been created from the page YAML header
        existing_content = element._type.nil? && !element.content.blank?

        # FIXME: we don't want to deal here with the generic Locomotive::EditableElement class
        element = page.editable_elements.with_same_class!(element, "Locomotive::#{attributes[:type].to_s.classify}".constantize)
        element.attributes = attributes

        # we know now this was an editable_text element. If it already had
        # a content, then it shouldn't be flagged as default_content.
        if element.respond_to?(:default_content?) && existing_content
          element.default_content = false
        end

        element
      else
        klass = "Locomotive::#{attributes[:type].to_s.classify}".constantize
        page.editable_elements.build(attributes, klass)
      end
    end

    # FIXME (Did): see comment on line 17.
    # def remove_useless_editable_elements(page, elements)
    #   if _elements = (elements.map { |p, _elements| p._id == page._id ? _elements : nil }.flatten.compact)
    #     page.editable_elements.where(:_id.nin => _elements.map(&:_id)).destroy_all
    #   end
    # end

    def assign_block_information(element, blocks)
      if element.block && (options = blocks[element.block])
        element.block_name      = element.block.split('/').last if options[:short_name]
        element.block_priority  = options[:priority]
      end
    end

    def services
      @services ||= Locomotive::Steam::Services.build_instance.tap do |services|
        services.set_site(self.site)
        services.locale = self.locale
      end
    end

    def repository
      services.repositories.page
    end

    def find_page(id, in_memory)
      in_memory[id] ||= Locomotive::Page.find(id)
    end

    def logger
      Rails.logger
    end

  end

end
