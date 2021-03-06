# -*- encoding: utf-8 -*-

require 'test/unit'
require 'webgen/tree'
require 'webgen/contentprocessor'

class TestContentProcessorHaml < Test::Unit::TestCase

  def test_call
    obj = Webgen::ContentProcessor::Haml.new
    root = Webgen::Node.new(Webgen::Tree.new.dummy_root, '/', '/')
    node = Webgen::Node.new(root, 'test', 'test')
    content = "#content\n  %h1 Hallo\n  = [node.absolute_lcn, ref_node.absolute_lcn, dest_node.absolute_lcn, website, context.dest_node.absolute_lcn].join"
    context = Webgen::ContentProcessor::Context.new(:content => content,
                                                    :chain => [node])
    obj.call(context)
    assert_equal("<div id='content'>\n  <h1>Hallo</h1>\n  /test/test/test/test\n</div>\n", context.content)

    context.content = "#cont\n  = unknown"
    assert_raise(RuntimeError) { obj.call(context) }
  end

end
