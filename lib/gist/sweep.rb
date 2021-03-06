require "gist/sweep/version"
require 'date'
require 'json'
require 'github_api'
require 'optparse'

module GistSweep
  class Sweep
    def parse_arguments()
      options = {
        :verbose => false,
        :config_file => "~/.gist-sweep",
        :public => false,
        :days => 90
      }

      OptionParser.new do |opts|
        opts.banner = "Usage: gist-sweep [options]"

        opts.on("-v", "-s", "Print verbose messages") do |v|
          options[:verbose] = v
        end

        opts.on("-c", "Read config from a different file") do |c|
          options[:config_file] = c
        end

        opts.on("-u", "Username to sweep gists on") do |u|
          options[:username] = u
        end

        opts.on("-d", "Days to keep", Integer) do |d|
          options[:days] = d.to_i
        end

        opts.on("-p", "Include public gists") do |p|
          options[:public] = p
        end

      end.parse!

      options
    end

    def read_config_from_file(path)
      expanded_path = File.expand_path(path)
      if File.exists?(expanded_path)
        contents = File.read(expanded_path)
        if contents.chomp.empty?
          {}
        else
          JSON.parse(contents)
        end
      else
        {}
      end
    end

    def write_config_file(oauth_token, path)
      expanded_path = File.expand_path(path)
      File.write(expanded_path, JSON.generate({:oauth_token => oauth_token}))
      FileUtils.chmod(0400, expanded_path)
    end

    def load_github_api(config, file_path)
      if config["oauth_token"] and !config["oauth_token"].empty?
        Github.new(:oauth_token => config["oauth_token"], :auto_pagination => true)
      else
        puts "You need to setup a 'Personal Access Token' to use with gist-sweep"
        puts "I'll wait for you to paste one in: "
        code = STDIN.gets.strip
        write_config_file(code, file_path)
        Github.new(:oauth_token => code, :auto_pagination => true)
      end
    end

    def promot_to_remove_gists(gists)
      gists.each { |g|
        puts "#{g["id"]} -- #{g["description"]}"
      }
      print "Remove #{gists.size} gists? (y/n) "
      line = STDIN.gets.strip
      if line == 'y'
        true
      else
        false
      end
    end

    def verbose_log(args, msg)
      if args[:verbose]
        puts msg
      end
    end

    def sweep(raw_args)
      args = parse_arguments()
      config = read_config_from_file(args[:config_file])
      github = load_github_api(config, args[:config_file])

      # Find out if there's a pattern passed in...
      arg_count =
        if raw_args.include?("-v")
          # If there's a -v passed in treat it as an arg like -u
          raw_args.size - 1
        else
          raw_args.size
        end

      pattern =
        if arg_count % 2 == 1
          raw_args[arg_count]
        end

      if args[:username]
        min_age = DateTime.now - args[:days]
        verbose_log(args, "Removing gists older than #{min_age}")

        pattern_matcher = Regexp.new(pattern || "")

        gists_to_remove = github.gists.list(args[:username]).body.select{ |g|
          keep_already = (!g["public"] or args[:public]) and (DateTime.parse(g["updated_at"]) < min_age)
          if pattern
            keep_already and pattern_matcher.match(g["description"])
          else
            keep_already
          end
        }

        if gists_to_remove.empty?
          puts "No gists to remove"
        else
          if promot_to_remove_gists(gists_to_remove)
            gists_to_remove.each { |g|
              verbose_log(args, "Deleting gist #{g["id"]}")
              github.gists.delete(g["id"])
            }
            puts "Swept gists."
          end
        end
      else
        abort "No username defined (with -u flag)."
      end
    end
  end
end
