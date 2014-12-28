require 'rugged'

module RedmineGitHosting
  module GitoliteHandlers
    class RepositoryReadmeCreator

      attr_reader :repository
      attr_reader :remote_branch


      def initialize(repository)
        @repository    = repository
        @remote_branch = "refs/heads/#{repository.extra[:default_branch]}"
      end


      def call
        if repository_empty?
          create_readme_file
        else
          logger.warn("Repository not empty, cannot create README file in path '#{repository.gitolite_repository_path}'")
        end
      end


      private


        def logger
          RedmineGitHosting.logger
        end


        def repository_empty?
          RedmineGitHosting::GitoliteWrapper.sudo_repository_empty?(repository.gitolite_repository_path)
        end


        def create_readme_file
          logger.info("Create README file for repository '#{repository.gitolite_repository_name}'")
          temp_dir = Dir.mktmpdir

          begin
            ## Clone repository
            repo = clone_repo(temp_dir)

            ## Create file
            index = create_file(repo)

            ## Create commit
            create_commit(repo, index)

            ## Push
            push_commit(repo)
          rescue => e
            logger.error("Error while creating README file for repository '#{repository.gitolite_repository_name}'")
            logger.error(e.message)
          ensure
            FileUtils.rm_rf temp_dir
          end
        end


        def clone_repo(temp_dir)
          Rugged::Repository.clone_at(repository.ssh_url, temp_dir, credentials: credentials)
        end


        def create_file(repo)
          oid = repo.write("## #{repository.gitolite_repository_name}", :blob)
          index = repo.index
          index.add(path: "README.md", oid: oid, mode: 0100644)
          index
        end


        def create_commit(repo, index)
          commit_tree = index.write_tree(repo)
          Rugged::Commit.create(repo,
            author:     commit_author,
            committer:  commit_author,
            message:    "Add README file",
            parents:    repo.empty? ? [] : [ repo.head.target ].compact,
            tree:       commit_tree,
            update_ref: 'HEAD'
          )
        end


        def push_commit(repo)
          repo.push('origin', [ remote_branch ], credentials: credentials)
        end


        def credentials
          Rugged::Credentials::SshKey.new(
            :username   => RedmineGitHosting::GitoliteWrapper.gitolite_user,
            :publickey  => RedmineGitHosting::GitoliteWrapper.gitolite_ssh_public_key,
            :privatekey => RedmineGitHosting::GitoliteWrapper.gitolite_ssh_private_key
          )
        end


        def commit_author
          @commit_author ||= {
            email: RedmineGitHosting::GitoliteWrapper.git_config_username,
            name:  RedmineGitHosting::GitoliteWrapper.git_config_email,
            time:  Time.now
          }
        end

    end
  end
end