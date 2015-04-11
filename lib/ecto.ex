defmodule Ecto do
  @moduledoc ~S"""
  Ecto is split into 3 main components:

    * `Ecto.Repo` - repositories are wrappers around the database.
      Via the repository, we can create, update, destroy and query existing entries.
      A repository needs an adapter and a URL to communicate to the database

    * `Ecto.Model` - models provide a set of functionalities for defining
      data structures, how changes are performed in the storage, life-cycle
      callbacks and more

    * `Ecto.Query` - written in Elixir syntax, queries are used to retrieve
      information from a given repository. Queries in Ecto are secure, avoiding
      common problems like SQL Injection, and also provide type safety. Queries
      are composable via the `Ecto.Queryable` protocol

  In the following sections, we will provide an overview of those components and
  how they interact with each other. Feel free to access their respective module
  documentation for more specific examples, options and configuration.

  If you want to quickly check a sample application using Ecto, please check
  https://github.com/elixir-lang/ecto/tree/master/examples/simple.

  ## Repositories

  `Ecto.Repo` is a wrapper around the database. We can define a
  repository as follows:

      defmodule Repo do
        use Ecto.Repo, otp_app: :my_app
      end

  Where the configuration for the Repo must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, Repo,
        adapter: Ecto.Adapters.Postgres,
        database: "ecto_simple",
        username: "postgres",
        password: "postgres",
        hostname: "localhost"

  Each repository in Ecto defines a `start_link/0` function that needs to be invoked
  before using the repository. In general, this function is not called directly,
  but used as part of your application supervision tree.

  If your application was generated with a supervisor (by passing `--sup` to `mix new`)
  you will have a `lib/my_app.ex` file containing the application start callback that
  defines and starts your supervisor. You just need to edit the `start/2` function to
  start the repo as a worker on the supervisor:

      def start(_type, _args) do
        import Supervisor.Spec

        children = [
          worker(Repo, [])
        ]

        opts = [strategy: :one_for_one, name: MyApp.Supervisor]
        Supervisor.start_link(children, opts)
      end

  ## Models

  Models provide a set of functionalities around structuring your data,
  defining relationships and applying changes to repositories.

  For now, we will cover two of those:

    * `Ecto.Schema` - provides the API necessary to define schemas
    * `Ecto.Changeset` - defines how models should be changed in the database

  Let's see an example:

      defmodule Weather do
        use Ecto.Model

        # weather is the DB table
        schema "weather" do
          field :city,    :string
          field :temp_lo, :integer
          field :temp_hi, :integer
          field :prcp,    :float, default: 0.0
        end
      end

  By defining a schema, Ecto automatically defines a struct with
  the schema fields:

      iex> weather = %Weather{temp_lo: 30}
      iex> weather.temp_lo
      30

  The schema also allows the model to interact with a repository:

      iex> weather = %Weather{temp_lo: 0, temp_hi: 23}
      iex> Repo.insert(weather)
      %Weather{...}

  After persisting `weather` to the database, it will return a new copy of
  `%Weather{}` with the primary key (the `id`) set. We can use this value
  to read a struct back from the repository:

      # Get the struct back
      iex> weather = Repo.get Weather, 1
      %Weather{id: 1, ...}

      # Update it
      iex> weather = %{weather | temp_lo: 10}
      iex> Repo.update(weather)
      %Weather{...}

      # Delete it
      iex> Repo.delete(weather)
      %Weather{...}

  > NOTE: by using `Ecto.Model`, an `:id` field with type `:integer` is
  > generated by default, which is the primary key of the Model. If you want
  > to use a different primary key, you can declare custom `@primary_key`
  > before the `schema/2` call. Consult the `Ecto.Schema` documentation
  > for more information.

  Notice how the storage (repository) and the data are decoupled. This provides
  two main benefits:

    * By having structs as data, we guarantee they are light-weight,
      serializable structures. In many languages, the data is often represented
      by large, complex objects, with entwined state transactions, which makes
      serialization, maintenance and understanding hard;

    * By making the storage explicit with repositories, we don't pollute the
      repository with unnecessary overhead, providing straight-forward and
      performant access to storage;

  ### Changesets

  Although in the example above we have directly inserted and updated the
  model in the repository, most of the times, developers will use changesets
  to perform those operations.

  Changesets allow developers to filter, cast, and validate changes before
  we apply them to a model. Imagine the given model:

      defmodule User do
        use Ecto.Model

        schema "users" do
          field :name
          field :email
          field :age, :integer
        end

        def changeset(user, params \\ nil) do
          user
          |> cast(params, ~w(name email), ~w(age))
          |> validate_format(:email, ~r/@/)
          |> validate_inclusion(:age, 0..130)
          |> validate_unique(:email, on: Repo)
        end
      end

  Since `Ecto.Model` by default imports `Ecto.Changeset` functions,
  we use them to generate and manipulate a changeset in the `changeset/2`
  function above.

  First we invoke `Ecto.Changeset.cast/4` with the model, the parameters
  and a list of required and optional fields; this returns a changeset.
  The parameter is a map with binary keys and a value that will be cast
  based on the type defined on the model schema.

  Any parameter that was not explicitly listed in the required or
  optional fields list will be ignored. Furthermore, if a field is given
  as required but it is not in the parameter map nor in the model, it will
  be marked with an error and the changeset is deemed invalid.

  After casting, the changeset is given to many `Ecto.Changeset.validate_*/2`
  functions that validate only the **changed fields**. In other words:
  if a field was not given as a parameter, it won't be validated at all.
  For example, if the params map contain only the "name" and "email" keys,
  the "age" validation won't run.

  As an example, let's see how we could use the changeset above in
  a web application that needs to update users:

      def update(id, params) do
        changeset = User.changeset Repo.get!(User, id), params["user"]

        if changeset.valid? do
          user = Repo.update(changeset)
          send_resp conn, 200, "Ok"
        else
          send_resp conn, 400, "Bad request"
        end
      end

  The `changeset/2` function receives the user model and its parameters
  and returns a changeset. If the changeset is valid, we persist the
  changes to the database, otherwise, we handle the error by emitting
  a bad request code.

  Another example to create users:

      def create(id, params) do
        changeset = User.changeset %User{}, params["user"]

        if changeset.valid? do
          user = Repo.insert(changeset)
          send_resp conn, 200, "Ok"
        else
          send_resp conn, 400, "Bad request"
        end
      end

  The benefit of having explicit changesets is that we can easily provide
  different changesets for different use cases. For example, one
  could easily provide specific changesets for create and update:

      def changeset(user, :create, params) do
        # Changeset on create
      end

      def changeset(user, :update, params) do
        # Changeset on update
      end

  ## Query

  Last but not least, Ecto allows you to write queries in Elixir and send
  them to the repository, which translates them to the underlying database.
  Let's see an example:

      import Ecto.Query, only: [from: 2]

      query = from w in Weather,
            where: w.prcp > 0 or is_nil(w.prcp),
           select: w

      # Returns %Weather{} structs matching the query
      Repo.all(query)

  Queries are defined and extended with the `from` macro. The supported
  keywords are:

    * `:distinct`
    * `:where`
    * `:order_by`
    * `:offset`
    * `:limit`
    * `:lock`
    * `:group_by`
    * `:having`
    * `:join`
    * `:select`
    * `:preload`

  Examples and detailed documentation for each of those are available in the
  `Ecto.Query` module.

  When writing a query, you are inside Ecto's query syntax. In order to
  access params values or invoke functions, you need to use the `^`
  operator, which is overloaded by Ecto:

      def min_prcp(min) do
        from w in Weather, where: w.prcp > ^min or is_nil(w.prcp)
      end

  Besides `Repo.all/1`, which returns all entries, repositories also
  provide `Repo.one/1`, which returns one entry or nil, and `Repo.one!/1`
  which returns one entry or raises.

  ## Other topics

  ### Mix tasks and generators

  Ecto provides many tasks to help your workflow as well as code generators.
  You can find all available tasks by typing `mix help` inside a project
  with Ecto listed as a dependency.

  Ecto generators will automatically open the generated files if you have
  `ECTO_EDITOR` set in your environment variable.

  ### Associations

  Ecto supports defining associations on schemas:

      defmodule Post do
        use Ecto.Model

        schema "posts" do
          has_many :comments, Comment
        end
      end

      defmodule Comment do
        use Ecto.Model

        schema "comments" do
          field :title, :string
          belongs_to :post, Post
        end
      end

  Once an association is defined, Ecto provides a couple conveniences. The
  first one is the `Ecto.Model.assoc/2` function that allows us to easily
  retrieve all associated data to a given struct:

      import Ecto.Model

      # Get all comments for the given post
      Repo.all assoc(post, :comments)

      # Or build a query on top of the associated comments
      query = from c in assoc(post, :comments), where: c.title != nil
      Repo.all(query)

  Ecto also supports joins with associations:

      query = from p in Post,
             join: c in assoc(p, :comments),
           select: {p, c}

      [{post, comment}] = Repo.all(query)

  When an association is defined, Ecto also defines a field in the model
  with the association name. By default, associations are not loaded into
  this field:

      iex> post = Repo.get(Post, 42)
      iex> post.comments
      #Ecto.Association.NotLoaded<...>

  However, developers can use the preload functionality in queries to
  automatically pre-populate the field:

      iex> post = Repo.get from(p in Post, preload: [:comments]), 42
      iex> post.comments
      [%Comment{...}, %Comment{...}]

  You can find more information about defining associations and each respective
  association module in `Ecto.Schema` docs.

  > NOTE: Ecto does not lazy load associations. While lazily loading associations
  > may sound convenient at first, in the long run it becomes a source of confusion
  > and performance issues.

  ### Migrations

  Ecto supports database migrations. You can generate a migration with:

      $ mix ecto.gen.migration create_posts

  This will create a new file inside `priv/repo/migrations` with the `up` and
  `down` functions. Check `Ecto.Migration` for more information.
  """
end
