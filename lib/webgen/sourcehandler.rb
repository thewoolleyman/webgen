# -*- encoding: utf-8 -*-

require 'webgen/loggable'
require 'benchmark'

module Webgen

  # Namespace for all classes that handle source paths.
  #
  # Have a look at Webgen::SourceHandler::Base for details on how to implement a source handler
  # class.
  module SourceHandler

    autoload :Base, 'webgen/sourcehandler/base'
    autoload :Copy, 'webgen/sourcehandler/copy'
    autoload :Directory, 'webgen/sourcehandler/directory'
    autoload :Metainfo, 'webgen/sourcehandler/metainfo'
    autoload :Template, 'webgen/sourcehandler/template'
    autoload :Page, 'webgen/sourcehandler/page'
    autoload :Fragment, 'webgen/sourcehandler/fragment'
    autoload :Virtual, 'webgen/sourcehandler/virtual'
    autoload :Feed, 'webgen/sourcehandler/feed'
    autoload :Sitemap, 'webgen/sourcehandler/sitemap'
    autoload :Memory, 'webgen/sourcehandler/memory'

    # This class is used by Website to do the actual rendering of the website. It
    #
    # * collects all source paths using the source classes
    # * creates nodes using the source handler classes
    # * writes changed nodes out using an output class
    class Main

      include WebsiteAccess
      include Loggable

      def initialize #:nodoc:
        website.blackboard.add_service(:create_nodes, method(:create_nodes))
        website.blackboard.add_service(:source_paths, method(:find_all_source_paths))
        website.blackboard.add_listener(:node_meta_info_changed?, method(:meta_info_changed?))
      end

      # Render the nodes provided in the +tree+. Before the actual rendering is done, the sources
      # are checked (nodes for deleted sources are deleted, nodes for new and changed sources).
      def render(tree)
        begin
          website.logger.mark_new_cycle if website.logger

          puts "Updating tree..."
          time = Benchmark.measure do
            website.cache.reset_volatile_cache
            update_tree(tree)
          end
          puts "...done in " + ('%2.4f' % time.real) + ' seconds'

          if !tree.root
            puts 'No source files found - maybe not a webgen website?'
            return nil
          end

          puts "Writing changed nodes..."
          time = Benchmark.measure do
            write_tree(tree)
          end
          puts "...done in " + ('%2.4f' % time.real) + ' seconds'
        end while tree.node_access[:alcn].any? {|name,node| node.flagged(:created) || node.flagged(:reinit)}
        :success
      end

      #######
      private
      #######

      # Update the +tree+ by creating/reinitializing all needed nodes.
      def update_tree(tree)
        unused_paths = Set.new
        begin
          used_paths = Set.new(find_all_source_paths.keys) - unused_paths
          paths_to_use = Set.new
          nodes_to_delete = Set.new

          tree.node_access[:alcn].each do |alcn, node|
            next if node == tree.dummy_root
            used_paths.delete(node.node_info[:src])

            deleted = !find_all_source_paths.include?(node.node_info[:src])
            if deleted
              nodes_to_delete << node
              #TODO: delete output path
            elsif (!node.flagged(:created) && find_all_source_paths[node.node_info[:src]].changed?) || node.meta_info_changed?
              node.flag(:reinit)
              paths_to_use << node.node_info[:src]
            elsif node.changed?
              # nothing to be done here
            end
          end

          nodes_to_delete.each {|node| tree.delete_node(node)}
          used_paths.merge(paths_to_use)
          paths = create_nodes_from_paths(tree, used_paths.to_a.sort)
          unused_paths.merge(used_paths - paths)
          tree.node_access[:alcn].each {|name, node| tree.delete_node(node) if node.flagged(:reinit)}
          website.cache.reset_volatile_cache
        end until used_paths.empty?
      end

      # Write out all changed nodes of the +tree+.
      def write_tree(tree)
        output = website.blackboard.invoke(:output_instance)

        tree.node_access[:alcn].select do |name, node|
          use_node = (node != tree.dummy_root && node.flagged(:dirty))
          node.unflag(:dirty_meta_info)
          node.unflag(:created)
          node.unflag(:dirty)
          use_node
        end.sort.each do |name, node|
          next if node['no_output'] || !(content = node.content)

          begin
            puts " "*4 + name, :verbose
            type = if node.is_directory?
                     :directory
                   elsif node.is_fragment?
                     :fragment
                   else
                     :file
                   end
            output.write(node.path, content, type)
          rescue
            raise RuntimeError, "Error while processing <#{node.absolute_lcn}>: #{$!.message}", $!.backtrace
          end
        end
      end

      # Return a hash with all source paths.
      def find_all_source_paths
        if !defined?(@paths)
          source = Webgen::Source::Stacked.new(website.config['sources'].collect do |mp, name, *args|
                                                 [mp, constant(name).new(*args)]
                                               end)
          @paths = {}
          source.paths.each do |path|
            if !(website.config['sourcehandler.ignore'].any? {|pat| File.fnmatch(pat, path, File::FNM_CASEFOLD|File::FNM_DOTMATCH)})
              @paths[path.source_path] = path
            end
          end
        end
        @paths
      end

      # Return only the subset of +paths+ which are handled by the source handler +name+.
      def paths_for_handler(name, paths)
        patterns = website.config['sourcehandler.patterns'][name]
        return [] if patterns.nil?

        options = (website.config['sourcehandler.casefold'] ? File::FNM_CASEFOLD : 0) |
          (website.config['sourcehandler.use_hidden_files'] ? File::FNM_DOTMATCH : 0)
        find_all_source_paths.values_at(*paths).select do |path|
          patterns.any? {|pat| File.fnmatch(pat, path, options)}
        end
      end

      # Use the source handlers to create nodes for the +paths+ in the +tree+.
      def create_nodes_from_paths(tree, paths)
        used_paths = Set.new
        website.config['sourcehandler.invoke'].sort.each do |priority, shns|
          shns.each do |shn|
            sh = website.cache.instance(shn)
            handler_paths = paths_for_handler(shn, paths)
            used_paths.merge(handler_paths)
            handler_paths.sort {|a,b| a.path.length <=> b.path.length}.each do |path|
              parent_dir = path.directory.split('/').collect {|p| Path.new(p).cn}.join('/')
              parent_dir += '/' if path != '/' && parent_dir == ''
              create_nodes(tree, parent_dir, path, sh)
            end
          end
        end
        used_paths
      end

      # Prepare everything to create nodes under the absolute lcn path +parent_path_name+ in the
      # +tree from the +path+ using the +source_handler+. If a block is given, the actual creation
      # of the nodes is deferred to it. After the nodes are created, it is also checked if they have
      # all needed properties.
      def create_nodes(tree, parent_path_name, path, source_handler) #:yields: parent, path
        if !(parent = tree[parent_path_name])
          raise "The specified parent path <#{parent_path_name}> does not exist"
        end
        path = path.dup
        path.meta_info = default_meta_info(path, source_handler.class.name)
        (website.cache[:sourcehandler_path_mi] ||= {})[[path.path, source_handler.class.name]] = path.meta_info.dup
        website.blackboard.dispatch_msg(:before_node_created, parent, path)
        *nodes = if block_given?
                   yield(parent, path)
                 else
                   source_handler.create_node(parent, path)
                 end
        nodes.flatten.compact.each do |node|
          website.blackboard.dispatch_msg(:after_node_created, node)
        end
        nodes
      end

      # Return the default meta info for the pair of +path+ and +sh_name+.
      def default_meta_info(path, sh_name)
        path.meta_info.merge(website.config['sourcehandler.default_meta_info'][:all]).
          merge(website.config['sourcehandler.default_meta_info'][sh_name] || {})
      end

      # Check if the default meta information for +node+ has changed since the last run. But don't
      # take the node's path's +modified_at+ meta information into account since that changes on
      # every path change.
      def meta_info_changed?(node)
        path = node.node_info[:creation_path]
        old_mi = website.cache[:sourcehandler_path_mi][[path, node.node_info[:processor]]]
        old_mi.delete('modified_at')
        new_mi = default_meta_info(@paths[path] || Webgen::Path.new(path), node.node_info[:processor])
        new_mi.delete('modified_at')
        node.flag(:dirty_meta_info) if !old_mi || old_mi != new_mi
      end

    end

  end

end
