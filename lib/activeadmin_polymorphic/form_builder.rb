module ActiveadminPolymorphic
  class FormBuilder < ::ActiveAdmin::FormBuilder
    def polymorphic_has_many(assoc, poly_name, options = {}, &block)
      PolymorphicHasManyBuilder.new(self, assoc, poly_name, options).render(&block)
    end
  end

  class PolymorphicHasManyBuilder < SimpleDelegator
    attr_reader :assoc
    attr_reader :options
    attr_reader :heading, :sortable_column, :sortable_start
    attr_reader :new_record, :destroy_option
    attr_reader :poly_name, :types, :path_prefix, :type_paths

    def initialize(has_many_form, assoc, poly_name, options)
      super has_many_form
      @assoc = assoc
      @options = extract_custom_settings!(options.dup)
      @options.reverse_merge!(for: assoc)
                                @options[:class] = [options[:class], "polymorphic_has_many_fields has_many_fields"].compact.join(' ')

                                if sortable_column
                                  @options[:for] = [assoc, sorted_children(sortable_column)]
                                end
                                @poly_name = poly_name
                              end

                              def render(&block)
                                html = "".html_safe
                                html << template.content_tag(:h3) { heading } if heading.present?
                                html << template.capture { content_polymorphic_has_many(&block) }
                                html = wrap_div_or_li(html)
                                template.concat(html) if template.output_buffer
                                html
                              end

                              protected

                              # remove options that should not render as attributes
                              def extract_custom_settings!(options)
                                @heading = options.key?(:heading) ? options.delete(:heading) : default_heading
                                @sortable_column = options.delete(:sortable)
                                @sortable_start  = options.delete(:sortable_start) || 0
                                @new_record = options.key?(:new_record) ? options.delete(:new_record) : true
                                @destroy_option = options.delete(:allow_destroy)
                                @types = options.delete(:types)
                                @path_prefix = options.delete(:path_prefix) || :admin
                                @type_paths  = options.delete(:type_paths) || {}
                                options
                              end

                              def default_heading
                                assoc_klass.model_name.
                                  human(count: ::ActiveAdmin::Helpers::I18n::PLURAL_MANY_COUNT)
                              end

                              def assoc_klass
                                @assoc_klass ||= __getobj__.object.class.reflect_on_association(assoc).klass
                              end

                              def content_polymorphic_has_many(&block)
                                form_block = proc do |form_builder|
                                  render_polymorphic_has_many_form(form_builder, options[:parent], &block)
                                end

                                template.assigns[:has_many_block] = true
                                contents = without_wrapper { inputs(options, &form_block) }
                                contents ||= "".html_safe

                                js = new_record ? js_for_polymorphic_has_many(assoc, poly_name, template, options[:class], &form_block) : ''
                                contents << js
                              end

                              # Renders the Formtastic inputs then appends ActiveAdmin delete and sort actions.
                              def render_polymorphic_has_many_form(form_builder, parent, &block)
                                index = parent && form_builder.send(:parent_child_index, parent)
                                form_builder.input("#{poly_name}_id", as: :hidden)

                                if form_builder.object.send(poly_name).nil?
                                  form_builder.input("#{poly_name}_type", input_html: { class: 'polymorphic_type_select' }, as: :select, collection: polymorphic_options)
                                else
                                  form_builder.input(
                                    "#{poly_name}_type", as: :hidden,
                                    input_html: {"data-path" =>  form_edit_path(form_builder.object.send(poly_name)) }
                                  )
                                end

                                template.concat template.capture { yield(form_builder, index) }
                                template.concat polymorphic_has_many_actions(form_builder, "".html_safe)
                              end

                              def polymorphic_has_many_actions(form_builder, contents)
                                if form_builder.object.new_record?
                                  contents << template.content_tag(:li) do
                                    template.link_to I18n.t('active_admin.has_many_remove'),
                                      "#", class: 'button polymorphic_has_many_remove'
                                  end
                                elsif allow_destroy?(form_builder.object)
                                  contents << form_builder.input(:_destroy, as: :boolean,
                                                                 wrapper_html: {class: 'polymorphic_has_many_delete'},
                                                                 label: I18n.t('active_admin.has_many_delete'))
                                end

                                if sortable_column
                                  form_builder.input sortable_column, as: :hidden

                                  contents << template.content_tag(:li, class: 'handle') do
                                    I18n.t('active_admin.move')
                                  end
                                end

                                contents
                              end

                              def allow_destroy?(form_object)
                                !! case destroy_option
                                when Symbol, String
                                  form_object.public_send destroy_option
                                when Proc
                                  destroy_option.call form_object
                                else
                                  destroy_option
                                end
                              end

                              def sorted_children(column)
                                __getobj__.object.public_send(assoc).sort_by do |o|
                                  attribute = o.public_send column
                                  [attribute.nil? ? Float::INFINITY : attribute, o.id || Float::INFINITY]
                                end
                              end

                              def without_wrapper
                                is_being_wrapped = already_in_an_inputs_block
                                self.already_in_an_inputs_block = false

                                html = yield

                                self.already_in_an_inputs_block = is_being_wrapped
                                html
                              end

                              def js_for_polymorphic_has_many(assoc, poly_name, template, class_string, &form_block)
                                assoc_name       = assoc_klass.model_name
                                placeholder      = "NEW_#{assoc_name.to_s.underscore.upcase.gsub(/\//, '_')}_RECORD"
                                opts = {
                                  for: [assoc, assoc_klass.new],
                                      class: class_string,
                                      for_options: { child_index: placeholder }
                                    }
                                    html = template.capture{ __getobj__.send(:inputs_for_nested_attributes, opts, &form_block) }
                                    text = new_record.is_a?(String) ? new_record : I18n.t('active_admin.has_many_new', model: assoc_name.human)

                                    template.link_to text, '#', class: "button polymorphic_has_many_add", data: {
                                      html: CGI.escapeHTML(html).html_safe, placeholder: placeholder
                                    }
                                  end

                                  def wrap_div_or_li(html)
                                    template.content_tag(already_in_an_inputs_block ? :li : :div,
                                                         html,
                                                         class: "polymorphic_has_many_container #{assoc}",
                                                         'data-sortable' => sortable_column,
                                                         'data-sortable-start' => sortable_start)
                                  end

                                  def polymorphic_options
                                    # add internationalization
                                    types.each_with_object([]) do |model, options|
                                      options << [
                                        model.model_name.human, model,
                                        {"data-path" => form_new_path(model) }
                                      ]
                                    end
                                  end

                                  def form_new_path(object)
                                    "/#{path_prefix}/#{type_paths.fetch(object, ActiveModel::Naming.plural(object))}/new"
                                  end

                                  def form_edit_path(object)
                                    "/#{path_prefix}/#{type_paths.fetch(object, ActiveModel::Naming.plural(object))}/#{object.id}/edit"
                                  end
                                  end
                                  end
