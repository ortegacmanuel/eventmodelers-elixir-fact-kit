defmodule MyApp.Command do
  @moduledoc """
  A command is an `embedded_schema` with the board's fields. `use MyApp.Command`
  gives it `new/2` and `changeset/2`: every field is required unless it's named
  in `optional:` (the fields with `optional: true` on the board).

      defmodule MyApp.Slices.RegisterPlot.RegisterPlot do
        use MyApp.Command, optional: [:note]

        embedded_schema do
          field :plot_id, :string
          field :name, :string
          field :note, :string
        end
      end

  `new(params, generated)` returns `{:ok, cmd}` or `{:error, changeset}`.
  `generated` carries what `context.ex` creates (ids, instants). A missing field
  is an error *key* — `{field, {"can't be blank", [validation: :required]}}` —
  and the screen turns it into words (`translate_error/1`, Gettext).

  A closed list or a format the field's description states goes in an
  override that keeps the default:

      def changeset(params, generated) do
        super(params, generated) |> validate_inclusion(:unit, ~w(kg t))
      end
  """

  import Ecto.Changeset

  defmacro __using__(opts) do
    optional = Keyword.get(opts, :optional, [])

    quote do
      use Ecto.Schema
      import Ecto.Changeset

      @primary_key false

      def new(params, generated \\ %{}),
        do: params |> changeset(generated) |> apply_action(:new)

      def changeset(params, generated \\ %{}),
        do: MyApp.Command.changeset(struct(__MODULE__), params, generated, unquote(optional))

      defoverridable changeset: 2
    end
  end

  @doc false
  def changeset(%mod{} = cmd, params, generated, optional) do
    fields = mod.__schema__(:fields)

    cmd
    |> cast(params, fields)
    |> change(generated)
    |> validate_required(fields -- optional)
  end
end
