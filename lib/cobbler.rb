#________________________________________

#

require 'json'
require 'uri'
require 'xmlrpc/client'

#

module Cobbler

  #

  class API

    attr_reader :client

    def initialize(args = {})
      @client        = nil
      @max_retries   = args.fetch('max_retries', default_args['max_retries'])
      url_candidate  = args.fetch('url', default_args['url'])
      begin
        @url         = URI(url_candidate)
      rescue ArgumentError
        raise "[ERROR] '#{url_candidate}' is not a valid URL."
      end
      connect
      self
    end

    def connect
      @client = XMLRPC::Client.new(
        @url.host,
        @url.path,
        @url.port
      ) if @client.nil?
      self
    end

    def default_args
      {
        'client'      => nil,
        'max_retries' => 5,
        'url'         => 'http://localhost/cobbler_api',
      }
    end

    def get_system(id_or_fqdn)
      method = 'get_system_by_' + (id_or_fqdn =~ /\./ ? 'fqdn' : 'id')
      self.send(method, id_or_fqdn)
    end

    def get_system_by_fqdn(fqdn)
      id_list = run_query('find_system', { 'hostname' => fqdn })
      case id_list
      when nil, '', '~', []
        Cobbler::System.new
      else
        get_system_by_id(id_list.first)
      end
    end

    def get_system_by_id(id)
      result = run_query('get_system', id)
      Cobbler::System.new(result.class == Hash ? result : {})
    end

    def run_query(action, query)
      connect
      def query_helper(action, query, retry_count)
        if retry_count > @max_retries
          nil
        else
          begin
            @client.call(action, query)
          rescue RuntimeError
            query_helper(action, query, retry_count+1)
          end
        end
      end
      query_helper(action, query, 0)
    end
  end

  #

  class System
    attr_reader :changes, :record

    def initialize(initial={})
      @changes = Set.new
      @record  = {}
      from_hash(initial, 'replace')
      @changes = Set.new
      self
    end

    def changed?
      @changes.count > 0
    end

    def comment(new_value={}, mode='merge', format='hash')
      hash_field('comment', normalize_hash(new_value), mode)
      case format
      when 'json', 'string'
        JSON.generate(@record['comment'])
      else
        @record['comment']
      end
    end

    def emit_edit
      edit_cmd = [
        'cobbler system edit',
        '--name', @record['name'],
      ]
      @changes.each do |field_name|
        edit_cmd << option_name(field_name)
        edit_cmd << "'#{self.send(field_name, {}, 'merge', 'string')}'"
      end
      puts(edit_cmd.join(' '))
    end

    def from_hash(hash={}, mode='replace')
      hash['comment'] = normalize_hash(hash.fetch('comment', {}))
      @record         = integrate_hashes(@record, hash, mode)
    end

    def from_json(json = '{}')
      JSON.parse(json)
    end

    def hash_field(field, new_value={}, mode='merge')
      before         = @record.fetch(field, {})
      @record[field] = integrate_hashes(before, new_value, mode)
      @changes << field unless @record[field] == before
      @record[field]
    end

    def integrate_hashes(original_hash, new_hash, mode='merge')
      case mode
      when 'merge'
        original_hash.merge(new_hash)
      when 'replace'
        new_hash
      end
    end

    def ks_meta(new_value={}, mode='merge', format='hash')
      hash_field('ks_meta', normalize_hash(new_value), mode)
      case format
      when 'hash'
        @record['ks_meta']
      when 'json'
        JSON.generate(@record['ks_meta'])
      when 'string'
        @record['ks_meta'].map { |k,v| k + '=' + v }.join(' ')
      end
    end

    def normalize_hash(hash_or_string)
      case
      when hash_or_string.class == Hash
        hash_or_string
      when hash_or_string.class == String
        from_json(hash_or_string)
      else
        {}
      end
    end

    def option_name(field_name)
      '--' + case field_name
             when 'ks_meta'
               'ksmeta'
             else
               field_name
             end
    end

    def to_hash
      @record
    end

    def to_json
      @record.to_json
    end

    def to_record
      @record.to_json
    end
  end
end
