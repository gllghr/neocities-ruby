# frozen_string_literal: true

require 'minitest/autorun'
require 'neocities'
require 'fileutils'
require 'tmpdir'

class CLITest < Minitest::Test
  def setup
    @mock_client = MockClient.new
    @temp_dir = Dir.mktmpdir('neocities_test')
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && Dir.exist?(@temp_dir)
  end

  def setup_test_files
    Dir.chdir(@temp_dir) do
      File.write('file1.txt', 'content 1')
      File.write('file2.txt', 'content 2')

      Dir.mkdir('dir_a')
      sub_file1 = File.join('dir_a', 'sub_file_1.txt')
      File.write(sub_file1, 'content sub_file_1')

      dir_b = File.join('dir_a', 'dir_b')
      Dir.mkdir(dir_b)
      sub_file2 = File.join(dir_b, 'sub_file_2.txt')
      File.write(sub_file2, 'content sub_file_2')

      Dir.mkdir('.hidden_dir')
      hidden_file = File.join('.hidden_dir', '.hidden_file')
      File.write(hidden_file, 'content hidden_file')
      File.write('.hidden_file', 'content hidden_file')
    end
  end

  def setup_git_repo
    Dir.chdir(@temp_dir) do
      # A git repo like you would get from 'git --init', with no object or commits
      Dir.mkdir('.git')
      Dir.mkdir('.git/objects')
      Dir.mkdir('.git/objects/info')
      Dir.mkdir('.git/objects/pack')
      Dir.mkdir('.git/refs')
      Dir.mkdir('.git/refs/heads')
      Dir.mkdir('.git/refs/tags')
      Dir.mkdir('.git/info')

      File.write('.git/HEAD', "ref: refs/heads/master\n")
      File.write('.git/config', <<~CONFIG)
        [core]
        	repositoryformatversion = 0
        	filemode = true
        	bare = false
        	logallrefupdates = true
      CONFIG
      File.write('.git/description', "Unnamed repository; edit this file 'description' to name the repository.\n")
    end
  end

  # Create a .gitignore file in the specified dir with the specified rules
  def setup_gitignore(dir, rules)
    Dir.chdir(@temp_dir) do
      gitignore_path = File.join(dir, '.gitignore')
      File.write(gitignore_path, "#{rules.join("\n")}\n")
    end
  end

  def assert_uploaded(local_path, remote_path = nil)
    files = @mock_client.uploaded_files.select do |file|
      File.identical?(Pathname(@temp_dir) + Pathname(local_path), Pathname(file[:cwd]) + file[:local])
    end

    assert_equal 1, files.size, "Expected #{local_path} to be uploaded"
    file = files[0]

    if remote_path
      assert_equal remote_path, file[:remote].to_s
    else
      assert_equal local_path, file[:remote].to_s
    end
  end

  def test_push_basic
    setup_test_files

    cli = Neocities::CLI.new(['push', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 6, @mock_client.uploaded_files.size
    assert_uploaded('file1.txt')
    assert_uploaded('file2.txt')
    assert_uploaded('dir_a/sub_file_1.txt')
    assert_uploaded('dir_a/dir_b/sub_file_2.txt')
    assert_uploaded('.hidden_file')
    assert_uploaded('.hidden_dir/.hidden_file')
  end

  def test_push_subdir
    setup_test_files

    cli = Neocities::CLI.new(['push', "#{@temp_dir}/dir_a"])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 2, @mock_client.uploaded_files.size
    assert_uploaded('dir_a/sub_file_1.txt', 'sub_file_1.txt')
    assert_uploaded('dir_a/dir_b/sub_file_2.txt', 'dir_b/sub_file_2.txt')
  end

  def test_push_relative_path
    setup_test_files

    Dir.chdir(@temp_dir) do
      cli = Neocities::CLI.new(['push', './'])

      cli.instance_variable_set(:@client, @mock_client)

      _out, err = capture_io { cli.push }
      assert_empty err

      assert_equal 6, @mock_client.uploaded_files.size
      assert_uploaded('file1.txt')
      assert_uploaded('file2.txt')
      assert_uploaded('dir_a/sub_file_1.txt')
      assert_uploaded('dir_a/dir_b/sub_file_2.txt')
      assert_uploaded('.hidden_file')
      assert_uploaded('.hidden_dir/.hidden_file')
    end
  end

  def test_push_exclude_files
    setup_test_files

    cli = Neocities::CLI.new(['push', '-e', 'file2.txt', '-e', '.hidden_file', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 4, @mock_client.uploaded_files.size
    assert_uploaded('file1.txt')
    assert_uploaded('dir_a/sub_file_1.txt')
    assert_uploaded('dir_a/dir_b/sub_file_2.txt')
    assert_uploaded('.hidden_dir/.hidden_file')
  end

  def test_push_exclude_directory
    setup_test_files

    cli = Neocities::CLI.new(['push', '-e', 'dir_a', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 4, @mock_client.uploaded_files.size
    assert_uploaded('file1.txt')
    assert_uploaded('file2.txt')
    assert_uploaded('.hidden_file')
    assert_uploaded('.hidden_dir/.hidden_file')
  end

  def test_push_exclude_directory_trailing_slash
    setup_test_files

    cli = Neocities::CLI.new(['push', '-e', 'dir_a/', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 4, @mock_client.uploaded_files.size
    assert_uploaded('file1.txt')
    assert_uploaded('file2.txt')
    assert_uploaded('.hidden_file')
    assert_uploaded('.hidden_dir/.hidden_file')
  end

  def test_push_exclude_directory_leading_dot_slash
    setup_test_files

    cli = Neocities::CLI.new(['push', '-e', './dir_a', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 4, @mock_client.uploaded_files.size
    assert_uploaded('file1.txt')
    assert_uploaded('file2.txt')
    assert_uploaded('.hidden_file')
    assert_uploaded('.hidden_dir/.hidden_file')
  end

  def test_push_gitignores
    setup_test_files
    setup_git_repo
    setup_gitignore('.', ['*2.txt', '!sub*2.txt'])
    setup_gitignore('dir_a', ['*1.txt'])

    cli = Neocities::CLI.new(['push', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 6, @mock_client.uploaded_files.size
    assert_uploaded('.gitignore')
    assert_uploaded('file1.txt')
    assert_uploaded('dir_a/.gitignore')
    assert_uploaded('dir_a/dir_b/sub_file_2.txt')
    assert_uploaded('.hidden_file')
    assert_uploaded('.hidden_dir/.hidden_file')
  end

  def test_push_nogitignore
    setup_test_files
    setup_git_repo
    setup_gitignore('.', ['*.txt'])

    cli = Neocities::CLI.new(['push', '--no-gitignore', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 10, @mock_client.uploaded_files.size
    assert_uploaded('.git/config')
    assert_uploaded('.git/description')
    assert_uploaded('.git/HEAD')
    assert_uploaded('.gitignore')
    assert_uploaded('file1.txt')
    assert_uploaded('file2.txt')
    assert_uploaded('dir_a/sub_file_1.txt')
    assert_uploaded('dir_a/dir_b/sub_file_2.txt')
    assert_uploaded('.hidden_file')
    assert_uploaded('.hidden_dir/.hidden_file')
  end

  def test_push_dry_run
    setup_test_files

    cli = Neocities::CLI.new(['push', '--dry-run', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    out, err = capture_io { cli.push }
    assert_empty err
    assert_empty @mock_client.uploaded_files
    assert_match(/Doing a dry run/, out)
  end

  def test_push_prune
    setup_test_files
    @mock_client.preexisting_files = ['to_remove1', 'dir_a/to_remove2']

    cli = Neocities::CLI.new(['push', '--prune', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 6, @mock_client.uploaded_files.size
    assert_uploaded('file1.txt')
    assert_uploaded('file2.txt')
    assert_uploaded('dir_a/sub_file_1.txt')
    assert_uploaded('dir_a/dir_b/sub_file_2.txt')
    assert_uploaded('.hidden_file')
    assert_uploaded('.hidden_dir/.hidden_file')

    assert_equal 2, @mock_client.deleted_files.size
    assert_includes @mock_client.deleted_files, 'to_remove1'
    assert_includes @mock_client.deleted_files, 'dir_a/to_remove2'
  end

  def test_push_prune_with_excludes
    setup_test_files
    @mock_client.preexisting_files = ['to_remove1', 'dir_a/sub_file_1.txt']

    cli = Neocities::CLI.new(['push', '-e', 'dir_a', '--prune', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 4, @mock_client.uploaded_files.size
    assert_uploaded('file1.txt')
    assert_uploaded('file2.txt')
    assert_uploaded('.hidden_file')
    assert_uploaded('.hidden_dir/.hidden_file')

    assert_equal 2, @mock_client.deleted_files.size
    assert_includes @mock_client.deleted_files, 'to_remove1'
    # Excluded file should get pruned
    assert_includes @mock_client.deleted_files, 'dir_a/sub_file_1.txt'
  end

  def test_push_prune_with_gitignores
    setup_test_files
    setup_git_repo
    setup_gitignore('.', ['*.txt'])
    @mock_client.preexisting_files = ['to_remove1', 'dir_a/sub_file_1.txt']

    cli = Neocities::CLI.new(['push', '--prune', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 3, @mock_client.uploaded_files.size
    assert_uploaded('.gitignore')
    assert_uploaded('.hidden_file')
    assert_uploaded('.hidden_dir/.hidden_file')

    assert_equal 2, @mock_client.deleted_files.size
    assert_includes @mock_client.deleted_files, 'to_remove1'
    # Ignored file should get pruned
    assert_includes @mock_client.deleted_files, 'dir_a/sub_file_1.txt'
  end

  def test_push_exclude_nonexistent
    # We shouldn't get any errors if we pass a non-existent file/dir as an
    # exclude. It should just be ignored.
    setup_test_files

    cli = Neocities::CLI.new(['push', '-e', 'nonexistent_dir', @temp_dir])

    cli.instance_variable_set(:@client, @mock_client)

    _out, err = capture_io { cli.push }
    assert_empty err

    assert_equal 6, @mock_client.uploaded_files.size
    assert_uploaded('file1.txt')
    assert_uploaded('file2.txt')
    assert_uploaded('dir_a/sub_file_1.txt')
    assert_uploaded('dir_a/dir_b/sub_file_2.txt')
    assert_uploaded('.hidden_file')
    assert_uploaded('.hidden_dir/.hidden_file')
  end

  def test_path_excluded
    cli = Neocities::CLI.new([])

    excluded_paths = ['./foo/', 'bar', 'a/b/c']
    cli.instance_variable_set(:@excluded_paths, excluded_paths)

    assert cli.path_excluded?('./foo')
    assert cli.path_excluded?('foo/')
    assert cli.path_excluded?('foo/bar')
    assert cli.path_excluded?('foo/bar/baz')
    assert cli.path_excluded?('bar')
    assert cli.path_excluded?('./bar')
    assert cli.path_excluded?('bar/')
    assert cli.path_excluded?('bar/baz/qux')
    assert cli.path_excluded?('a/b/c')
    assert cli.path_excluded?('a/b/c/d')

    refute cli.path_excluded?('a')
    refute cli.path_excluded?('fo')
    refute cli.path_excluded?('foobar')
    refute cli.path_excluded?('food/bar')
    refute cli.path_excluded?('./food')
    refute cli.path_excluded?('a/d')
    refute cli.path_excluded?('a/b/d')
  end

  class MockClient
    attr_reader :uploaded_files, :deleted_files
    attr_accessor :preexisting_files

    def initialize
      @uploaded_files = []
      @deleted_files = []
      @preexisting_files = []
    end

    def upload(path, remote_path, dry_run = false)
      unless dry_run
        @uploaded_files << {
          local: path,
          remote: remote_path,
          cwd: Dir.pwd
        }
      end
      { result: 'success' }
    end

    def delete_wrapper_with_dry_run(path, dry_run = false)
      @deleted_files << path.to_s unless dry_run
      { result: 'success' }
    end

    def list
      { files: @preexisting_files.map { |p| { path: p } } }
    end
  end
end
