#
# these methods are made available in capistrano tasks as 'leap.method_name'
# (see RemoteCommand::new_capistrano)
#

module LeapCli; module Remote; module LeapPlugin

  def required_packages
    "puppet ruby-hiera-puppet rsync lsb-release"
  end

  def log(*args, &block)
    LeapCli::Util::log(*args, &block)
  end

  #
  # creates directories that are owned by root and 700 permissions
  #
  def mkdirs(*dirs)
    raise ArgumentError.new('illegal dir name') if dirs.grep(/[\' ]/).any?
    run dirs.collect{|dir| "mkdir -m 700 -p #{dir}; "}.join
  end

  def assert_initialized
    begin
      test_initialized_file = "test -f #{INITIALIZED_FILE}"
      check_required_packages = "! dpkg-query -W --showformat='${Status}\n' #{required_packages} 2>&1 | grep -q -E '(deinstall|no packages)'"
      run "#{test_initialized_file} && #{check_required_packages} && echo ok"
    rescue Capistrano::CommandError => exc
      LeapCli::Util.bail! do
        exc.hosts.each do |host|
          LeapCli::Util.log :error, "running deploy: node not initialized. Run 'leap node init #{host}'", :host => host
        end
      end
    end
  end

  def mark_initialized
    run "touch #{INITIALIZED_FILE}"
  end

  #
  # This is a hairy ugly hack, exactly the kind of stuff that makes ruby
  # dangerous and too much fun for its own good.
  #
  # In most places, we run remote ssh without a current 'task'. This works fine,
  # except that in a few places, the behavior of capistrano ssh is controlled by
  # the options of the current task.
  #
  # We don't want to create an actual current task, because tasks are no fun
  # and can't take arguments or return values. So, when we need to configure
  # things that can only be configured in a task, we use this handy hack to
  # fake the current task.
  #
  # This is NOT thread safe, but could be made to be so with some extra work.
  #
  def with_task(name)
    task = @config.tasks[name]
    @config.class.send(:alias_method, :original_current_task, :current_task)
    @config.class.send(:define_method, :current_task, Proc.new(){ task })
    begin
      yield
    ensure
      @config.class.send(:remove_method, :current_task)
      @config.class.send(:alias_method, :current_task, :original_current_task)
    end
  end

  #
  # similar to run(cmd, &block), but with:
  #
  # * exit codes
  # * stdout and stderr are combined
  #
  def stream(cmd, &block)
    command = '%s 2>&1; echo "exitcode=$?"' % cmd
    run(command) do |channel, stream, data|
      exitcode = nil
      if data =~ /exitcode=(\d+)\n/
        exitcode = $1.to_i
        data.sub!(/exitcode=(\d+)\n/,'')
      end
      yield({:host => channel[:host], :data => data, :exitcode => exitcode})
    end
  end

  #
  # like stream, but capture all the output before returning
  #
  def capture(cmd, &block)
    command = '%s 2>&1; echo "exitcode=$?" 2>&1;' % cmd
    host_data = {}
    run(command) do |channel, stream, data|
      host_data[channel[:host]] ||= ""
      if data =~ /exitcode=(\d+)\n/
        exitcode = $1.to_i
        data.sub!(/exitcode=(\d+)\n/,'')
        host_data[channel[:host]] += data
        yield({:host => channel[:host], :data => host_data[channel[:host]], :exitcode => exitcode})
      else
        host_data[channel[:host]] += data
      end
    end
  end

  #
  # Run a command, with a nice status report and progress indicator.
  # Only successful results are returned, errors are printed.
  #
  # For each successful run on each host, block is yielded with a hash like so:
  #
  # {:host => 'bluejay', :exitcode => 0, :data => 'shell output'}
  #
  def run_with_progress(cmd, &block)
    ssh_failures = []
    exitcode_failures = []
    succeeded = []
    task = LeapCli.log_level > 1 ? :standard_task : :skip_errors_task
    with_task(task) do
      log :querying, 'facts' do
        progress "   "
        call_on_failure do |host|
          ssh_failures << host
          progress 'F'
        end
        capture(cmd) do |response|
          if response[:exitcode] == 0
            progress '.'
            yield response
          else
            exitcode_failures << response
            progress 'F'
          end
        end
      end
    end
    puts "done"
    if ssh_failures.any?
      log :failed, 'to connect to nodes: ' + ssh_failures.join(' ')
    end
    if exitcode_failures.any?
      log :failed, 'to run successfully:' do
        exitcode_failures.each do |response|
          log "[%s] exit %s - %s" % [response[:host], response[:exitcode], response[:data].strip]
        end
      end
    end
  rescue Capistrano::RemoteError => err
    log :error, err.to_s
  end

  private

  def progress(str='.')
    $stdout.print str; $stdout.flush;
  end

  #def mkdir(dir)
  #  run "mkdir -p #{dir}"
  #end

  #def chown_root(dir)
  #  run "chown root -R #{dir} && chmod -R ag-rwx,u+rwX #{dir}"
  #end

  #def logrun(cmd)
  #  @streamer ||= LeapCli::Remote::LogStreamer.new
  #  run cmd do |channel, stream, data|
  #    @streamer.collect_output(channel[:host], data)
  #  end
  #end

#    return_code = nil
#    run "something; echo return code: $?" do |channel, stream, data|
#      if data =~ /return code: (\d+)/
#        return_code = $1.to_i
#      else
#        Capistrano::Configuration.default_io_proc.call(channel, stream, data)
#      end
#    end
#    puts "finished with return code: #{return_code}"

end; end; end