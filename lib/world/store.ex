defmodule World.Store do
  @moduledoc """
  The store of the files of a warehouse (`docs/world.md`, "What is
  real"). The stock of a warehouse (`World.Stock`) counts its items; the
  store keeps the files of each model, by the name of the model. Three
  kinds:

  - `:memory`: the memory of the VM. The files are in the process of the
    storekeeper.
  - `:bucket`: an R2 bucket. On this computer, a folder (`dir`) is in
    place of the bucket, as for the photos of Phượt.
  - `:release`: the catalog in the release (`priv/models`). It is read
    only: a put is refused.

  The file of a model is `NAME.glb`, the GLB at the near level. A name has
  only letters, digits, `.`, `_` and `-`: it is never a path.
  """

  defstruct kind: :memory, dir: nil, files: %{}

  @name ~r/\A[A-Za-z0-9_.-]+\z/

  @doc "A store in the memory of the VM."
  def memory, do: %__MODULE__{kind: :memory}

  @doc "A bucket: a folder on this computer in place of the R2 bucket. The folder is made when it is missing."
  def bucket(dir) do
    File.mkdir_p!(dir)
    %__MODULE__{kind: :bucket, dir: dir}
  end

  @doc "The catalog of a release: the folder of its models (`priv/models` by default)."
  def release(dir \\ Application.app_dir(:world, "priv/models")), do: %__MODULE__{kind: :release, dir: dir}

  @doc "Put the files of a model: `{:ok, store}`, or `{:error, :read_only}` for a release."
  def put(%__MODULE__{kind: :release}, _name, _files), do: {:error, :read_only}
  def put(%__MODULE__{kind: :memory} = s, name, files), do: {:ok, %{s | files: Map.put(s.files, check(name), files)}}

  def put(%__MODULE__{kind: :bucket} = s, name, files) do
    File.write!(path(s, name), files)
    {:ok, s}
  end

  @doc "The files of a model: `{:ok, files}`, or `:error` when the store does not have them."
  def get(%__MODULE__{kind: :memory} = s, name), do: Map.fetch(s.files, check(name))

  def get(%__MODULE__{} = s, name) do
    case File.read(path(s, name)) do
      {:ok, files} -> {:ok, files}
      {:error, _} -> :error
    end
  end

  @doc "Each model in the store, with the bytes of its files, by its name."
  def list(%__MODULE__{kind: :memory} = s), do: s.files |> Enum.map(fn {k, v} -> {k, byte_size(v)} end) |> Enum.sort()

  def list(%__MODULE__{dir: dir}) do
    for file <- Enum.sort(File.ls!(dir)),
        Path.extname(file) == ".glb",
        do: {Path.rootname(file), File.stat!(Path.join(dir, file)).size}
  end

  defp path(s, name), do: Path.join(s.dir, check(name) <> ".glb")

  defp check(name) do
    if Regex.match?(@name, name), do: name, else: raise(ArgumentError, "not a name of a model: #{inspect(name)}")
  end
end
