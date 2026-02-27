RSpec.shared_examples "validates presence of" do |field|
  it { is_expected.to validate_presence_of(field) }
end

RSpec.shared_examples "validates uniqueness of" do |field, options = {}|
  it do
    validation = validate_uniqueness_of(field)
    validation = validation.scoped_to(options[:scoped_to]) if options[:scoped_to]
    validation = validation.case_insensitive if options[:case_insensitive]
    is_expected.to validation
  end
end

RSpec.shared_examples "validates numericality of" do |field, options = {}|
  it do
    validation = validate_numericality_of(field)
    validation = validation.only_integer if options[:only_integer]
    is_expected.to validation
  end
end
