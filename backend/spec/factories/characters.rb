FactoryBot.define do
  factory :character do
    name       { "Testchar" }
    realm      { "illidan" }
    region     { "us" }
    blizzard_id { "123456" }
  end
end