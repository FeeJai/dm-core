module DataMapper
  class Query
    module Conditions
      class InvalidOperation < ArgumentError; end

      class Operation
        # @api semipublic
        def self.new(slug, *operands)
          if klass = operation_class(slug)
            klass.new(*operands)
          else
            raise ArgumentError, "No Operation class for `#{slug.inspect}' has been defined"
          end
        end

        # @api semipublic
        def self.operation_class(slug)
          operation_classes[slug] ||= AbstractOperation.descendants.detect { |operation_class| operation_class.slug == slug }
        end

        # @api private
        def self.slugs
          @slugs ||= AbstractOperation.descendants.map { |operation_class| operation_class.slug }
        end

        class << self
          private

          # @api private
          def operation_classes
            @operation_classes ||= {}
          end
        end
      end # class Operation

      class AbstractOperation
        include Extlib::Assertions
        include Enumerable
        extend Equalizer

        equalize :slug, :sorted_operands

        # @api semipublic
        attr_reader :parent

        # @api semipublic
        attr_reader :operands

        # @api semipublic
        alias children operands

        # @api private
        def self.descendants
          @descendants ||= Set.new
        end

        # @api private
        def self.inherited(operation_class)
          descendants << operation_class
        end

        # @api semipublic
        def self.slug(slug = nil)
          slug ? @slug = slug : @slug
        end

        # Return the comparison class slug
        #
        # @return [Symbol]
        #   the comparison class slug
        #
        # @api private
        def slug
          self.class.slug
        end

        # @api semipublic
        def parent=(parent)
          clear_memoized_values
          @parent = parent
        end

        # @api semipublic
        def each
          @operands.each { |*block_args| yield(*block_args) }
          self
        end

        # @api semipublic
        def valid?
          @operands.any? && @operands.all? { |operand| valid_operand?(operand) }
        end

        # @api semipublic
        def <<(operand)
          assert_valid_operand(operand)
          unless operand.nil?
            operand.parent = self if operand.respond_to?(:parent=)
            @operands << operand
          end
          self
        end

        # @api semipublic
        def merge(operands)
          operands.each { |operand| self << operand }
          self
        end

        # @api semipublic
        def clear
          @operands.clear
          self
        end

        # @api semipublic
        def to_s
          return '' if empty?
          "(#{sort_by { |operand| operand.to_s }.join(" #{slug.to_s.upcase} ")})"
        end

        # @api private
        def negated?
          return @negated if defined?(@negated)
          @negated = parent ? parent.negated? : false
        end

        # Return a list of operands in predictable order
        #
        # @return [Array<AbstractOperation>]
        #   list of operands sorted in deterministic order
        #
        # @api private
        def sorted_operands
          @operands.sort_by { |operand| operand.hash }
        end

        private

        # @api semipublic
        def initialize(*operands)
          @operands = Set.new
          merge(operands)
        end

        # @api semipublic
        def initialize_copy(*)
          @operands = @operands.map { |operand| operand.dup }.to_set
        end

        # @api private
        def clear_memoized_values
          remove_instance_variable(:@negated) if defined?(@negated)
        end

        # @api private
        def assert_valid_operand(operand)
          assert_kind_of 'operand', operand, Conditions::AbstractOperation, Conditions::AbstractComparison, Array
        end

        # @api private
        def valid_operand?(operand)
          if operand.respond_to?(:valid?)
            operand.valid?
          else
            true
          end
        end
      end # class AbstractOperation

      module FlattenOperation
        # @api semipublic
        def <<(operand)
          if operand.kind_of?(self.class)
            merge(operand.operands)
          else
            super
          end
        end
      end # module FlattenOperation

      class AndOperation < AbstractOperation
        include FlattenOperation

        slug :and

        # @api semipublic
        def matches?(record)
          @operands.all? { |operand| operand.matches?(record) }
        end
      end # class AndOperation

      class OrOperation < AbstractOperation
        include FlattenOperation

        slug :or

        # @api semipublic
        def matches?(record)
          @operands.any? { |operand| operand.matches?(record) }
        end

        # @api semipublic
        def valid?
          @operands.any? { |operand| valid_operand?(operand) }
        end
      end # class OrOperation

      class NotOperation < AbstractOperation
        slug :not

        # @api semipublic
        def matches?(record)
          not operand.matches?(record)
        end

        # @api semipublic
        def <<(operand)
          assert_one_operand(operand)
          super
        end

        # @api semipublic
        def operand
          @operands.to_a.first
        end

        # @api private
        def negated?
          return @negated if defined?(@negated)
          @negated = parent ? !parent.negated? : true
        end

        # @api semipublic
        def to_s
          if operand
            "NOT(#{operand.to_s})"
          else
            ''
          end
        end

        private

        # @api private
        def assert_one_operand(operand)
          if self.operand && self.operand != operand
            raise ArgumentError, "#{self.class} cannot have more than one operand"
          end
        end
      end # class NotOperation

      class NullOperation < AbstractOperation
        undef_method :<<
        undef_method :merge

        slug :null

        # Match the record
        #
        # @param [Resource] record
        #   the resource to match
        #
        # @return [true]
        #   every record matches
        #
        # @api semipublic
        def matches?(record)
          record.kind_of?(Hash) || record.kind_of?(Resource)
        end

        # Test validity of the operation
        #
        # @return [true]
        #   always valid
        #
        # @api semipublic
        def valid?
          true
        end

        # Treat the operation the same as nil
        #
        # @return [true]
        #   should be treated as nil
        #
        # @api semipublic
        def nil?
          true
        end

        # Inspecting the operation should return the same as nil
        #
        # @return [String]
        #   return the string 'nil'
        #
        # @api semipublic
        def inspect
          'nil'
        end

        private

        # @api semipublic
        def initialize
          @operands = Set.new
        end
      end
    end # module Conditions
  end # class Query
end # module DataMapper
