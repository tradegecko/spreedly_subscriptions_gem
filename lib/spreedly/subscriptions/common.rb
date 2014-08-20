Dir[File.dirname(__FILE__) + '/../../vendor/*'].each do |directory|
  next unless File.directory?(directory)
  $LOAD_PATH.unshift File.expand_path(directory + '/lib')
end

require 'uri'
require 'bigdecimal'
require 'active_support/hash_with_indifferent_access'
require 'spreedly/subscriptions/version'

module Spreedly
  module Subscriptions

    class BaseResource
      attr_reader :attributes

      def initialize(attributes={})
        @attributes = ActiveSupport::HashWithIndifferentAccess.new(attributes)
      end

      def id
        @attributes[:id]
      end

      def method_missing(method, *args)
        if method.to_s =~ /\?$/
          send(method.to_s[0..-2], *args)
        elsif @attributes.key?(method.to_sym)
          @attributes[method.to_sym]
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        if method.to_s =~ /\?$/
          respond_to?(method.to_s[0..-2])
        else
          @attributes.key?(method.to_sym) || super
        end
      end
    end

    # Generates a subscribe url for the given user id and plan.
    # Options:
    #   :screen_name => a screen name for the user (shows up in the admin UI)
    #   :email => pre-populate the email field
    #   :first_name => pre-populate the first name field
    #   :last_name => pre-populate the last name field
    def self.subscribe_url(id, plan, options={})
      %w(screen_name email first_name last_name return_url).each do |option|
        options[option.to_sym] &&= URI.escape(options[option.to_sym])
      end

      screen_name = options.delete(:screen_name)
      params = %w(email first_name last_name return_url).select{|e| options[e.to_sym]}.collect{|e| "#{e}=#{options[e.to_sym]}"}.join('&')

      url = "https://subs.pinpayments.com/#{site_name}/subscribers/#{id}/subscribe/#{plan}"
      url << "/#{screen_name}" if screen_name
      url << '?' << params unless params == ''

      url
    end

    # Generates an edit subscriber for the given subscriber token. The
    # token is returned with the subscriber info (i.e. by
    # Subscriber.find).
    def self.edit_subscriber_url(token, return_url = nil)
      "https://subs.pinpayments.com/#{site_name}/subscriber_accounts/#{token}" +
      if return_url
        "?return_url=#{URI.escape(return_url)}"
      else
        ''
      end
    end

    def self.to_xml_params(hash) # :nodoc:
      hash.collect do |key, value|
        tag = key.to_s.tr('_', '-')
        result = "<#{tag}>"
        if value.is_a?(Hash)
          result << to_xml_params(value)
        elsif value.is_a?(Array)
          result << value.map { |val| to_xml_params(val) }.join("")
        else
          result << value.to_s
        end
        result << "</#{tag}>"
        result
      end.join('')
    end
  end
end
