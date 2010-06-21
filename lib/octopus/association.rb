module Octopus::Association
  def self.extended(base)
    base.send(:include, InstanceMethods)
  end

  module InstanceMethods
    def reload_connection()
      set_connection() if self.respond_to?(:current_shard)      
    end
    
    def save(*)
      reload_connection()
      super
    end

    def save!(*)
      reload_connection()
      super
    end

    def delete
      reload_connection()
      super
    end

    def destroy
      reload_connection()
      super
    end

    def update_attribute(name, value)
      reload_connection()
      super(name, value)
    end

    def update_attributes(attributes)
      reload_connection()
      super(attributes)
    end

    def update_attributes!(attributes)
      reload_connection()
      super(attributes)
    end

    def increment(attribute, by=1)
      reload_connection()
      super(attribute, by)
    end

    def increment!(attribute, by=1)
      reload_connection()
      super(attribute, by)
    end

    def decrement(attribute, by=1)
      reload_connection()
      super(attribute, by)
    end

    def decrement!(attribute, by=1)
      reload_connection()
      super(attribute, by)
    end

    def toggle(attribute)
      reload_connection()
      super(attribute)
    end

    def toggle!(attribute)
      reload_connection() 
      super(attribute)
    end
  end

  def collection_reader_method(reflection, association_proxy_class)
    define_method(reflection.name) do |*params|
      force_reload = params.first unless params.empty?
      reload_connection() 

      association = association_instance_get(reflection.name)

      unless association
        association  = association_proxy_class.new(self, reflection)
        association_instance_set(reflection.name, association)
      end

      reflection.klass.uncached { association.reload } if force_reload

      association
    end

    def association_constructor_method(constructor, reflection, association_proxy_class)
      define_method("#{constructor}_#{reflection.name}") do |*params|
        reload_connection() 
        attributees      = params.first unless params.empty?
        replace_existing = params[1].nil? ? true : params[1]
        association      = association_instance_get(reflection.name)

        unless association
          association = association_proxy_class.new(self, reflection)
          association_instance_set(reflection.name, association)
        end

        if association_proxy_class == ActiveRecord::Associations::HasOneAssociation
          return_val = association.send(constructor, attributees, replace_existing)
        else
          return_val = association.send(constructor, attributees)
        end
        
        if self.respond_to?(:current_shard) 
          return_val.current_shard = self.current_shard
        end

        return_val
      end
    end

    def association_accessor_methods(reflection, association_proxy_class)
      define_method(reflection.name) do |*params|
        force_reload = true
        reload_connection() 
        association = association_instance_get(reflection.name)

        if association.nil? || force_reload
          association =  self.class.connection_proxy.run_query_on_shard(self.current_shard) { association_proxy_class.new(self, reflection) }
          retval = if self.respond_to?(:current_shard) && self.current_shard != nil
            force_reload ? reflection.klass.uncached { self.class.connection_proxy.run_query_on_shard(self.current_shard) { association.reload } } : association.reload
          end
          if retval.nil? and association_proxy_class == ActiveRecord::Associations::BelongsToAssociation
            association_instance_set(reflection.name, nil)
            return nil
          end
          association_instance_set(reflection.name, association)
        end

        association
        #association.target.nil? ? nil : association
      end

      define_method("loaded_#{reflection.name}?") do
        reload_connection() 
        association = association_instance_get(reflection.name)
        association && association.loaded?
      end

      define_method("#{reflection.name}=") do |new_value|
        reload_connection() 
        association = association_instance_get(reflection.name)

        if association.nil? || association.target != new_value
          association = association_proxy_class.new(self, reflection)
        end

        association.replace(new_value)
        association_instance_set(reflection.name, new_value.nil? ? nil : association)
      end

      define_method("set_#{reflection.name}_target") do |target|
        return if target.nil? and association_proxy_class == ActiveRecord::Associations::BelongsToAssociation
        reload_connection() 
        association = association_proxy_class.new(self, reflection)
        association.target = target
        association_instance_set(reflection.name, association)
      end
    end


    define_method("#{reflection.name.to_s.singularize}_ids") do
      reload_connection()        
      if send(reflection.name).loaded? || reflection.options[:finder_sql]
        send(reflection.name).map(&:id)
      else
        if reflection.through_reflection && reflection.source_reflection.belongs_to?
          through = reflection.through_reflection
          primary_key = reflection.source_reflection.primary_key_name
          send(through.name).select("DISTINCT #{through.quoted_table_name}.#{primary_key}").map!(&:"#{primary_key}")
        else
          send(reflection.name).select("#{reflection.quoted_table_name}.#{reflection.klass.primary_key}").except(:includes).map!(&:id)
        end
      end
    end
  end
end



ActiveRecord::Base.extend(Octopus::Association)