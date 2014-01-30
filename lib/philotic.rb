require 'awesome_print'
require 'active_support/all'

require 'pathname'

require 'log4r'
require 'log4r/yamlconfigurator'
require 'log4r/outputter/datefileoutputter'
require 'log4r/outputter/syslogoutputter'
include Log4r

module Philotic
  mattr_accessor :logger
  mattr_accessor :log_event_handler

  CONNECTION_OPTIONS = [
      :rabbit_host,
      :connection_failed_handler,
      :connection_loss_handler,
      :timeout,
  ]
  EXCHANGE_OPTIONS = [
      :exchange_name,
      :message_return_handler,
  ]
  MESSAGE_OPTIONS = [
      :routing_key,
      :persistent,
      # :immediate,
      :mandatory,
      :content_type,
      :content_encoding,
      :priority,
      :message_id,
      :correlation_id,
      :reply_to,
      :type,
      :user_id,
      :app_id,
      :timestamp,
      :expiration,
  ]

  EVENTBUS_HEADERS = [
      :philotic_firehose,
      :philotic_product,
      :philotic_component,
      :philotic_event_type,
  ]

  DEFAULT_NAMED_QUEUE_OPTIONS = {
      :auto_delete => false,
      :durable => true
  }
  DEFAULT_ANONYMOUS_QUEUE_OPTIONS = {
      :auto_delete => true,
      :durable => false
  }

  DEFAULT_SUBSCRIBE_OPTIONS = {}

  def self.root
    ::Pathname.new File.expand_path('../../', __FILE__)
  end

  def self.env
    ENV['SERVICE_ENV'] || 'development'
  end

  def self.exchange
    Philotic::Connection.exchange
  end

  def self.initialize_named_queue!(queue_name, arguments_list, &block)
    raise "ENV['INITIALIZE_NAMED_QUEUE'] must equal 'true' to run Philotic.initialize_named_queue!" unless ENV['INITIALIZE_NAMED_QUEUE'] == 'true'
    connect! do
      queue_options = Philotic::DEFAULT_NAMED_QUEUE_OPTIONS
      arguments_list = [arguments_list] if !arguments_list.is_a? Array
      AMQP.channel.queue(queue_name, queue_options) do |old_queue|
        old_queue.delete do
          Philotic::Connection.close do
            connect! do
              Philotic.logger.info "deleted old queue. queue:#{queue_name}"
              AMQP.channel.queue(queue_name, queue_options) do |q|
                Philotic.logger.info "Created queue. queue:#{q.name}"
                arguments_list.each_with_index do |arguments, arguments_index|
                  q.bind(exchange, {arguments: arguments}) do
                    Philotic.logger.info "Added binding to queue. queue:#{q.name} binding:#{arguments}"
                    if arguments_index >= arguments_list.size - 1
                      Philotic.logger.info "Finished adding bindings to queue. queue:#{q.name}"
                      block.call(q) if block
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  def self.logger
    @@logger ||= init_logger
  end

  def self.init_logger
    Logger.new("/dev/null")
  end

  def self.on_publish_event(&block)
    @@log_event_handler = block
  end

  def self.log_event_published(severity, metadata, payload, message)
    if @@log_event_handler
      @@log_event_handler.call(severity, metadata, payload, message)
    else
      logger.send(severity, "#{message}; message_metadata:#{metadata}, payload:#{payload.to_json}")
    end
  end

  def self.connected?
    Philotic::Connection.connected?
  end

  def self.connect! &block
    Philotic::Connection.connect! &block
  end
end

require 'philotic/connection'
require 'philotic/version'
require 'philotic/config'
require 'philotic/routable'
require 'philotic/event'
require 'philotic/publisher'
require 'philotic/subscriber'