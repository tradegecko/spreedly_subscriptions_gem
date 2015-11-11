require 'spreedly/subscriptions/common'

raise "Real Spreedly already required!" if defined?(Spreedly::REAL)

module Spreedly
  module Subscriptions
    MOCK = "mock"

    def self.configure(name, token)
      @site_name = name
    end

    def self.site_name
      @site_name
    end

    class Resource < BaseResource
      def self.attributes
        @attributes ||= {}
      end

      def self.attributes=(value)
        @attributes = value
      end

      def initialize(attributes={})
        default_attrs = self.class.attributes.inject({}){|a,(k,v)| a[k.to_sym] = v.call; a}
        super(default_attrs.merge(attributes))
      end
    end

    class Subscriber < Resource
      self.attributes = {
        :created_at => proc{Time.now},
        :token => proc{(rand * 1000).round},
        :active => proc{false},
        :store_credit => proc{BigDecimal("0.0")},
        :active_until => proc{nil},
        :feature_level => proc{""},
        :on_trial => proc{false},
        :recurring => proc{false},
        :eligible_for_free_trial => proc{false}
      }

      def self.wipe! # :nodoc: all
        @subscribers = nil
      end

      def self.create!(id, *args) # :nodoc: all
        optional_attrs = args.last.is_a?(::Hash) ? args.pop : {}
        email, screen_name = args
        sub = new({:customer_id => id, :email => email, :screen_name => screen_name}.merge(optional_attrs))

        if subscribers[sub.id]
          raise "Could not create subscriber: already exists."
        end

        subscribers[sub.id] = sub
        sub
      end

      def self.delete!(id)
        subscribers.delete(id)
      end

      def self.find(id)
        subscribers[id]
      end

      def self.subscribers
        @subscribers ||= {}
      end

      def self.all
        @subscribers.values
      end

      def self.transactions(id)
        []
      end

      def initialize(params={})
        super
        if !id || id == ''
          raise "Could not create subscriber: Customer ID can't be blank."
        end
        @invoices ||= []
      end

      def id
        @attributes[:customer_id]
      end

      def update(args)
        args.each_pair do |key, value|
          if @attributes.has_key?(key)
            @attributes[key] = value
          end
        end
      end

      def comp(quantity, units, feature_level=nil)
        raise "Could not comp subscriber: no longer exists." unless self.class.find(id)
        raise "Could not comp subscriber: validation failed." unless units && quantity
        current_active_until = (active_until || Time.now)
        @attributes[:active_until] = case units
                                     when 'days'
                                       current_active_until + (quantity.to_i * 86400)
                                     when 'months'
                                       current_active_until + (quantity.to_i * 30 * 86400)
                                     end
        @attributes[:feature_level] = feature_level if feature_level
        @attributes[:active] = true
      end

      def activate_free_trial(plan_id)
        raise "Could not activate free trial for subscriber: validation failed. missing subscription plan id" unless plan_id
        raise "Could not active free trial for subscriber: subscriber or subscription plan no longer exists." unless self.class.find(id) && SubscriptionPlan.find(plan_id)
        raise "Could not activate free trial for subscriber: subscription plan either 1) isn't a free trial, 2) the subscriber is not eligible for a free trial, or 3) the subscription plan is not enabled." if (on_trial? and !eligible_for_free_trial?)
        @attributes[:on_trial] = true
        plan = SubscriptionPlan.find(plan_id)
        comp(plan.duration_quantity, plan.duration_units, plan.feature_level)
      end

      def allow_free_trial
        @attributes[:eligible_for_free_trial] = true
      end

      def stop_auto_renew
        raise "Could not stop auto renew for subscriber: subscriber does not exist." unless self.class.find(id)
        @attributes[:recurring] = false
      end

      def subscribe(plan_id, card_number="4222222222222")
        plan = SubscriptionPlan.find(plan_id)
        @invoices.unshift(Invoice.new(
          amount: (@invoices.select{|invoice| invoice.closed?}.size > 0 ? 0 : plan.amount),
          closed: false
        ))

        return unless card_number == "4222222222222"

        @invoices.first.attributes[:closed] = true
        @attributes[:recurring] = true
        comp(plan.duration_quantity, plan.duration_units, plan.feature_level)
      end

      def add_fee(args)
        raise "Unprocessable Entity" unless (args.keys & [:amount, :group, :name]).size == 3
        raise "Unprocessable Entity" unless active?
        nil
      end

      def invoices
        @invoices
      end

      def transactions
        @transactions
      end

      def last_successful_invoice
        @invoices.detect{|invoice| invoice.closed?}
      end
    end

    class Invoice < Resource
    end

    class Transaction < Resource
    end

    class SubscriptionPlan < Resource
      self.attributes = {
        :plan_type => proc{'regular'},
        :feature_level => proc{''}
      }

      def self.all
        plans.values
      end

      def self.find(id)
        plans[id.to_i]
      end

      def self.plans
        @plans ||= {
          1 => new(
            :id => 1,
            :name => 'Default mock plan',
            :duration_quantity => 1,
            :duration_units => 'days',
            :amount => 6
          ),
            2 => new(
              :id => 2,
              :name => 'Test Free Trial Plan',
              :plan_type => 'free_trial',
              :duration_quantity => 1,
              :duration_units => 'days',
              :amount => 11
          ),
            3 => new(
              :id => 3,
              :name => 'Test Regular Plan',
              :duration_quantity => 1,
              :duration_units => 'days',
              :amount => 17
          )
        }
      end

      def trial?
        (plan_type == "free_trial")
      end
    end

  end
end
