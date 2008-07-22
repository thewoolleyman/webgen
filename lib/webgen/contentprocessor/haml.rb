module Webgen::ContentProcessor

  # Processes content in Haml markup using the +haml+ library.
  class Haml

    # Convert the content in +haml+ markup to HTML.
    def call(context)
      require 'haml'

      locals = {
        :context => context,
        :node => context.content_node,
        :ref_node => context.ref_node,
        :dest_node => context.dest_node,
      }
      context.content = ::Haml::Engine.new(context.content, :filename => context.ref_node.absolute_lcn).
        render(Object.new, locals)
      context
    rescue Exception => e
      raise "Error converting Haml markup to HTML: #{e.message}"
    end

  end

end
