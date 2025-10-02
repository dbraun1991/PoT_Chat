# lib/pot_chat/crypto.ex
defmodule PoTChat.Crypto do
  @moduledoc """
  Cryptographic functions using Ed25519 for signing and verification.
  """

  # Generate a new keypair for a node
  def generate_keypair do
    :crypto.generate_key(:eddsa, :ed25519)
  end

  # Sign data with private key
  def sign(data, private_key) do
    :crypto.sign(:eddsa, :sha512, data, [private_key, :ed25519])
  end

  # Verify signature with public key
  def verify(data, signature, public_key) do
    :crypto.verify(:eddsa, :sha512, data, signature, [public_key, :ed25519])
  end

  # Hash data using SHA256
  def hash(data) do
    :crypto.hash(:sha256, data)
    |> Base.encode16(case: :lower)
  end

  # Generate message ID from message components
  def generate_message_id(content, author_id, timestamp) do
    hash("#{content}#{author_id}#{timestamp}")
  end
end