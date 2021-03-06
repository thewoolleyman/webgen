# -*- encoding: utf-8 -*-

require 'uri'
require 'yaml'

module Webgen::SourceHandler

  # Handles files which contain specifications for "virtual" nodes, ie. nodes that don't have real
  # source path.
  #
  # This can be used, for example, to provide multiple links to the same node.
  class Virtual

    include Base
    include Webgen::WebsiteAccess

    def initialize # :nodoc:
      website.blackboard.add_listener(:node_meta_info_changed?, method(:node_meta_info_changed?))
      @path_data = {}
    end

    # Create all virtual nodes under +parent+ which are specified in +path+.
    def create_node(parent, path)
      nodes = []
      read_data(path).each do |key, meta_info|
        cache_data = [key, meta_info.dup]

        key = Webgen::Common.absolute_path(key, parent.absolute_lcn) + (key =~ /\/$/ ? '/' : '')
        temp_parent = create_directories(parent.tree.root, File.dirname(key), path)

        output_path = meta_info.delete('url') || key
        output_path = (URI::parse(output_path).absolute? || output_path =~ /^\// ?
                       output_path : File.join(temp_parent.absolute_lcn, output_path))

        if key =~ /\/$/
          nodes << create_directory(temp_parent, key, path, meta_info)
        else
          nodes += website.blackboard.invoke(:create_nodes, parent.tree, temp_parent.absolute_lcn,
                                             Webgen::Path.new(key, path.source_path), self) do |cn_parent, cn_path|
            cn_path.meta_info.update(meta_info)
            super(cn_parent, cn_path, output_path) do |n|
              n.node_info[:sh_virtual_cache_data] = cache_data
            end
          end
        end
      end
      nodes.compact
    end

    #######
    private
    #######

    # Read the entries from the virtual file +data+ and yield the path, and the meta info hash for
    # each entry. The +parent+ parameter is used for making absolute path values if relative ones
    # are given.
    def read_data(path)
      if !@path_data.has_key?(path) || path.changed?
        page = page_from_path(path)
        @path_data[path] = YAML::load(page.blocks['content'].content).collect do |key, meta_info|
          meta_info ||= {}
          meta_info['modified_at'] = path.meta_info['modified_at']
          meta_info['no_output'] = true
          [key, meta_info]
        end if page.blocks.has_key?('content')
        @path_data[path] ||= []
      end
      @path_data[path]
    end

    # Create the needed parent directories for a virtual node.
    def create_directories(parent, dirname, path)
      dirname.sub(/^\//, '').split('/').each do |dir|
        parent = create_directory(parent, File.join(parent.absolute_lcn, dir), path)
      end
      parent
    end

    # Create a virtual directory if it does not already exist.
    def create_directory(parent, dir, path, meta_info = nil)
      dir_handler = website.cache.instance('Webgen::SourceHandler::Directory')
      website.blackboard.invoke(:create_nodes, parent.tree, parent.absolute_lcn,
                                Webgen::Path.new(File.join(dir, '/'), path.source_path),
                                dir_handler) do |par, temp_path|
        parent = dir_handler.node_exists?(par, temp_path)
        if (parent && (parent.node_info[:src] == path.source_path) && !meta_info.nil?) ||
            !parent
          temp_path.meta_info.update(meta_info) if meta_info
          parent.flag(:reinit) if parent
          parent = dir_handler.create_node(par, temp_path)
        end
        parent
      end
      parent
    end

    # Check if the +node+ is virtual and if, if its meta information has changed. This can only be
    # the case if the node has been recreated in this run.
    def node_meta_info_changed?(node)
      path = website.blackboard.invoke(:source_paths)[node.node_info[:src]]
      return if node.node_info[:processor] != self.class.name || !path.changed?

      old_data = node.node_info[:sh_virtual_cache_data]
      new_data = read_data(path).find {|key, mi| key == old_data.first}
      node.flag(:dirty_meta_info) if !new_data || old_data.last != new_data.last
    end

  end

end
