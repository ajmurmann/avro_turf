# This shared example expects a registry variable to be defined
# with an instance of the registry class being tested.
shared_examples_for "a schema registry client" do
  let(:logger) { Logger.new(StringIO.new) }
  let(:registry_url) { "http://registry.example.com" }
  let(:subject_name) { "some-subject" }
  let(:schema) do
    {
      type: "record",
      name: "person",
      fields: [
        { name: "name", type: "string" }
      ]
    }.to_json
  end

  before do
    stub_request(:any, /^#{registry_url}/).to_rack(FakeSchemaRegistryServer)
    FakeSchemaRegistryServer.clear
  end

  describe "#register and #fetch" do
    it "allows registering a schema" do
      id = registry.register(subject_name, schema)
      fetched_schema = registry.fetch(id)

      expect(fetched_schema).to eq(schema)
    end

    context "with an Avro::Schema" do
      let(:avro_schema) { Avro::Schema.parse(schema) }

      it "allows registration using an Avro::Schema" do
        id = registry.register(subject_name, avro_schema)
        expect(registry.fetch(id)).to eq(avro_schema.to_s)
      end

      context "with ActiveSupport present" do
        before do
          break_to_json(avro_schema)
        end

        it "allows registering an Avro schema" do
          id = registry.register(subject_name, avro_schema)
          expect(registry.fetch(id)).to eq(avro_schema.to_s)
        end
      end
    end
  end

  describe "#fetch" do
    context "when the schema does not exist" do
      it "raises an error" do
        expect do
          registry.fetch(-1)
        end.to raise_error(Excon::Errors::NotFound)
      end
    end
  end

  describe "#subjects" do
    it "lists the subjects in the registry" do
      subjects = Array.new(2) { |n| "subject#{n}" }
      subjects.each { |subject| registry.register(subject, schema) }
      expect(registry.subjects).to be_json_eql(subjects.to_json)
    end
  end

  describe "#subject_versions" do
    it "lists all the versions for the subject" do
      2.times do |n|
        registry.register(subject_name,
                          { type: :record, name: "r#{n}", fields: [] }.to_json)
      end
      expect(registry.subject_versions(subject_name))
        .to be_json_eql((1..2).to_a.to_json)
    end

    context "when the subject does not exist" do
      let(:subject_name) { 'missing' }

      it "raises an error" do
        expect do
          registry.subject_versions(subject_name).inspect
        end.to raise_error(Excon::Errors::NotFound)
      end
    end
  end

  describe "#subject_version" do
    before do
      2.times do |n|
        registry.register(subject_name,
                          { type: :record, name: "r#{n}", fields: [] }.to_json)
      end
    end
    let(:expected) do
      {
        name: subject_name,
        version: 1,
        schema: { type: :record, name: "r0", fields: [] }.to_json
      }.to_json
    end

    it "returns a specific version of a schema" do
      expect(registry.subject_version(subject_name, 1))
        .to eq(JSON.parse(expected))
    end

    context "when the version is not specified" do
      let(:expected) do
        {
          name: subject_name,
          version: 2,
          schema: { type: :record, name: "r1", fields: [] }.to_json
        }.to_json
      end

      it "returns the latest version" do
        expect(registry.subject_version(subject_name))
          .to eq(JSON.parse(expected))
      end
    end

    context "when the subject does not exist" do
      it "raises an error" do
        expect do
          registry.subject_version('missing')
        end.to raise_error(Excon::Errors::NotFound)
      end
    end

    context "when the version does not exist" do
      it "raises an error" do
        expect do
          registry.subject_version(subject_name, 3)
        end.to raise_error(Excon::Errors::NotFound)
      end
    end
  end

  describe "#check" do
    context "when the schema exists" do
      let!(:schema_id) { registry.register(subject_name, schema) }
      let(:expected) do
        {
          subject: subject_name,
          id: schema_id,
          version: 1,
          schema: schema
        }.to_json
      end
      it "returns the schema details" do
        expect(registry.check(subject_name, schema)).to eq(JSON.parse(expected))
      end

      context "with an Avro::Schema" do
        let(:avro_schema) { Avro::Schema.parse(schema) }

        it "supports a check using an Avro schema" do
          expect(registry.check(subject_name, avro_schema)).to eq(JSON.parse(expected))
        end

        context "with ActiveSupport present" do
          before { break_to_json(avro_schema) }

          it "supports a check using an Avro schema" do
            expect(registry.check(subject_name, avro_schema)).to eq(JSON.parse(expected))
          end
        end
      end
    end

    context "when the schema is not registered" do
      it "returns nil" do
        expect(registry.check("missing", schema)).to be_nil
      end
    end
  end

  # Monkey patch an Avro::Schema to simulate the presence of
  # active_support/core_ext.
  def break_to_json(avro_schema)
    def avro_schema.to_json(*args)
      instance_variables.each_with_object(Hash.new) do |ivar, result|
        result[ivar.to_s.sub('@', '')] = instance_variable_get(ivar)
      end.to_json(*args)
    end
  end
end
