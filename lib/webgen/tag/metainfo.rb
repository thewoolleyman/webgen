# -*- encoding: utf-8 -*-

module Webgen::Tag

  # Provides easy access to the meta information of a node.
  class Metainfo

    include Base

    # Return the meta information key specified in +tag+ of the content node.
    def call(tag, body, context)
      output = ''
      if tag == 'lang'
        output = context.content_node.lang
      elsif context.content_node[tag]
        output = context.content_node[tag].to_s
      else
        log(:warn) { "No value for meta info key '#{tag}' in <#{context.ref_node.absolute_lcn}> found in <#{context.content_node.absolute_lcn}>" }
      end
      output
    end

  end

end
