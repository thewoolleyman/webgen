config = Webgen::WebsiteAccess.website.config

# General configuration parameters
config.website.dir('.', :doc => 'The website directory, always needs to be set! Defaults to current working directory')
config.website.lang('en', :doc => 'The default language used for the website')

# All things regarding logging
config.logger.mask(nil, :doc => 'Only show logging events which match the regexp mask')

# All things regarding sources
config.sources [['/', "Webgen::Source::FileSystem", 'src']], :doc => 'One or more sources from which files are read, relative to website directory'

# All things regarding source handler
config.sourcehandler.patterns({
                                'Webgen::SourceHandler::Copy' => ['**/*.css', '**/*.js', '**/*.html', '**/*.gif', '**/*.jpg', '**/*.png'],
                                'Webgen::SourceHandler::Directory' => ['**/'],
                                'Webgen::SourceHandler::Metainfo' => ['**/metainfo', '**/*.metainfo']
                              }, :doc => 'Source handler to path pattern map')
config.sourcehandler.invoke({
                              1 => ['Webgen::SourceHandler::Directory', 'Webgen::SourceHandler::Metainfo', 'Webgen::SourceHandler::Directory'],
                              5 => ['Webgen::SourceHandler::Copy']
                            }, :doc => 'All source handlers listed here are used by webgen and invoked according to their priority setting')
config.sourcehandler.casefold(true, :doc => 'Specifies whether path are considered to be case-sensitive')
config.sourcehandler.use_hidden_files(false, :doc => 'Specifies whether hidden files (those starting with a dot) are used')
config.sourcehandler.ignore(['**/*~', '**/.svn/**'], :doc => 'Path patterns that should be ignored')

# All things regarding output
config.output ["Webgen::Output::FileSystem", 'output'], :doc => 'The class which is used to output the generated paths.'


# All things regarding content processors
config.contentprocessors({
                           'maruku' => 'Webgen::ContentProcessor::Maruku'
                         }, :doc => 'Content processor name to class map')

Webgen::WebsiteAccess.website.blackboard.add_service(:content_processor_names, Webgen::ContentProcessor.method(:list))
Webgen::WebsiteAccess.website.blackboard.add_service(:content_processor, Webgen::ContentProcessor.method(:for_name))
