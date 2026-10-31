defmodule World.StoreTest do
  use ExUnit.Case, async: true

  alias World.{Stock, Store}

  @moduletag :tmp_dir

  test "the memory of the VM keeps the files of each model" do
    s = Store.memory()
    assert Store.get(s, "van") == :error
    {:ok, s} = Store.put(s, "van", "glTF van")
    {:ok, s} = Store.put(s, "seat", "glTF")
    assert Store.get(s, "van") == {:ok, "glTF van"}
    assert Store.list(s) == [{"seat", 4}, {"van", 8}]
  end

  test "a bucket is a folder on this computer", %{tmp_dir: dir} do
    s = Store.bucket(Path.join(dir, "world"))
    assert Store.get(s, "van") == :error
    {:ok, s} = Store.put(s, "van", "glTF van")
    assert File.read!(Path.join(dir, "world/van.glb")) == "glTF van"
    assert Store.get(s, "van") == {:ok, "glTF van"}
    assert Store.list(s) == [{"van", 8}]
  end

  test "a release is read only, and only its GLB files are models", %{tmp_dir: dir} do
    File.write!(Path.join(dir, "van.glb"), "glTF van")
    File.write!(Path.join(dir, "van.far.glb"), "glTF")
    File.write!(Path.join(dir, "van.parts.json"), "[]")
    s = Store.release(dir)
    assert Store.put(s, "seat", "glTF") == {:error, :read_only}
    assert Store.list(s) == [{"van.far", 4}, {"van", 8}]
    assert Store.release().dir == Application.app_dir(:world, "priv/models")

    # The stock of a catalog: each model one time, and always full.
    stock = Stock.catalog(s)
    assert Stock.count(stock, "model:van") == 1 and Stock.free(stock) == 0
    assert Stock.files(stock, "model:van") == {:ok, "glTF van"}
    assert Stock.put_files(stock, "model:seat", "glTF") == {:error, :read_only}
  end

  test "a name of a model is never a path" do
    assert_raise ArgumentError, fn -> Store.put(Store.memory(), "../van", "glTF") end
    assert_raise ArgumentError, fn -> Store.get(Store.memory(), "a/b") end
  end

  test "the stock keeps the files of a model in its store, in its limit" do
    stock = Stock.new(10)
    assert Stock.files(stock, "model:van") == {:error, :missing}
    {:ok, stock} = Stock.put_files(stock, "model:van", "glTF van")
    assert Stock.files(stock, "model:van") == {:ok, "glTF van"}
    assert Stock.used(stock) == 8
    assert Stock.put_files(stock, "model:seat", "glTF") == {:error, :full}
    assert Stock.model("van") == "model:van"
  end
end
