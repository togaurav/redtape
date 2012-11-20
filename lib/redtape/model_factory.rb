module Redtape
  class ModelFactory
    attr_reader :model_accessor, :records_to_save

    def initialize(model_accessor)
      @model_accessor = model_accessor
      @records_to_save = []
    end

    def populate_model_using(params)
      model = find_or_create_root_model_from(params)
      populate(model, params)
    end

    protected

    # API hook to map request parameters (truncated from the attributes for this
    # record on down) onto the provided record instance.
    def populate_individual_record(record, attrs)
      # #merge! didn't work here....
      record.attributes = record.attributes.merge(attrs)
    end

    # API hook used to look up an existing record given its AssociationProxy
    # and all of the form parameters relevant to this record.
    def find_associated_model(attrs, args = {})
      case args[:with_macro]
      when :has_many
        args[:on_association].find(attrs[:id])
      when :has_one
        args[:for_model].send(args[:for_association_name])
      end
    end

    private

    # Factory method for root object
    def find_or_create_root_model_from(params)
      model_class = model_accessor.to_s.camelize.constantize
      if params[:id]
        model_class.send(:find, params[:id])
      else
        model_class.new
      end
    end

    def populate(model, attributes)
      populate_individual_record(
        model,
        params_for_current_nesting_level_only(attributes)
      )

      attributes.each do |key, value|
        next unless refers_to_association?(value)

        association = model.class.reflect_on_association(association_name_in(key).to_sym)

        case association.macro
        when :has_many
          populate_has_many(
            :in_association   => association_name_in(key),
            :for_model        => model,
            :using            => has_many_attrs_array_from(value)
          )
        when :has_one
          populate_has_one(
            :in_association   => association_name_in(key),
            :for_model        => model,
            :using            => value
          )
        when :belongs_to
          fail "Implement me"
        else
          fail "How did you get here anyway?"
        end

      end

      model
    end

    def populate_has_many(args = {})
      attrs, association_name, model = args.values_at(:using, :in_association, :for_model)

      attrs.each do |record_attrs|
        child_model = find_or_initialize_associated_model(
          record_attrs,
          :for_association_name => association_name,
          :with_macro           => :has_many,
          :on_model             => model
        )

        if child_model.new_record?
          model.send(association_name).send("<<", child_model)
        end

        populate_individual_record(
          child_model,
          params_for_current_nesting_level_only(record_attrs)
        )
      end
    end

    def populate_has_one(args = {})
      attrs, association_name, model = args.values_at(:using, :in_association, :for_model)

      child_model = find_or_initialize_associated_model(
        attrs,
        :for_association_name => association_name,
        :with_macro           => :has_one,
        :on_model             => model
      )

      if child_model.new_record?
        model.send("#{association_name}=", child_model)
      end

      populate_individual_record(
        child_model,
        params_for_current_nesting_level_only(attrs)
      )
    end

    def find_or_initialize_associated_model(attrs, args = {})
      association_name, macro, model = args.values_at(:for_association_name, :with_macro, :on_model)

      association = model.send(association_name)
      if attrs[:id]
        find_associated_model(
          attrs,
          :for_model => model,
          :with_macro => macro,
          :on_association => association,
        ).tap do |record|
          records_to_save << record
        end
      else
        case macro
        when :has_many
          model.send(association_name).build
        when :has_one
          model.send("build_#{association_name}")
        end
      end
    end

    def refers_to_association?(value)
      value.is_a?(Hash)
    end

    def params_for_current_nesting_level_only(attrs)
      attrs.dup.reject { |_, v| v.is_a? Hash }
    end

    ATTRIBUTES_KEY_REGEXP = /^(.+)_attributes$/

    def has_many_association_attrs?(key)
      key =~ ATTRIBUTES_KEY_REGEXP
    end

    def association_name_in(key)
      ATTRIBUTES_KEY_REGEXP.match(key)[1]
    end

    def has_many_attrs_array_from(fields_for_hash)
      fields_for_hash.values.clone
    end
  end
end
