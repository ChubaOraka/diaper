# == Schema Information
#
# Table name: barcode_items
#
#  id               :bigint(8)        not null, primary key
#  value            :string
#  barcodeable_id   :integer
#  quantity         :integer
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  organization_id  :integer
#  global           :boolean          default(FALSE)
#  barcodeable_type :string           default("Item")
#

RSpec.shared_examples "common barcode tests" do |barcode_item_factory|
  describe "item >" do
    it "is invalid without an item associated with it" do
      barcode = build(barcode_item_factory)
      barcode.item = nil
      expect(barcode).not_to be_valid
    end
  end

  describe "quantity >" do
    it "is not nil" do
      expect(build(barcode_item_factory, quantity: nil)).not_to be_valid
    end
    it "is an integer" do
      expect(build(barcode_item_factory, quantity: "aaa")).not_to be_valid
    end
    it "is not a negative number" do
      expect(build(barcode_item_factory, quantity: -1)).not_to be_valid
    end
  end

  describe "value >" do
    it "requires a value" do
      expect(build(barcode_item_factory, value: nil)).not_to be_valid
    end
  end
end

RSpec.describe BarcodeItem, type: :model do
  context "Global barcodes" do
    let(:canonical_item) { create(:canonical_item) }
    let(:global_barcode_item) { create(:global_barcode_item, barcodeable: canonical_item) }

    it "updates a counter in CanonicalItem whenever it tracks a new barcode" do
      expect do
        create(:global_barcode_item, barcodeable: canonical_item)
      end.to change { canonical_item.barcode_count }.to(1)
    end

    # These are scopes that are expressly to integrate with Filterable
    context "filters >" do
      it "->barcodeable_id shows only barcodes for a specific barcodeable_id" do
        global_barcode_item          # initial creation
        create(:global_barcode_item) # create a null case
        results = BarcodeItem.barcodeable_id(canonical_item.id)
        expect(results.length).to eq(1)
        expect(results.first).to eq(global_barcode_item)
      end
      it "#by_canonical_item_partner_key returns barcodes that match the partner key" do
        c1 = create(:canonical_item, partner_key: "foo")
        c2 = create(:canonical_item, partner_key: "bar")
        b1 = create(:global_barcode_item, barcodeable: c1)
        create(:global_barcode_item, barcodeable: c2)
        expect(BarcodeItem.by_canonical_item_partner_key("foo").first).to eq(b1)
      end
      it "->by_value returns the barcode with that value" do
        b1 = create(:global_barcode_item, value: "DEADBEEF")
        create(:global_barcode_item, value: "IDDQD")
        expect(BarcodeItem.by_value("DEADBEEF").first).to eq(b1)
      end
    end

    context "scopes >" do
      it "->include_global indicates if it should include the global barcodes as well" do
        global_barcode_item   # initial creation
        create(:barcode_item) # create a null case
        expect(BarcodeItem.include_global(false).length).to eq(1)
        expect(BarcodeItem.include_global(true).length).to eq(2)
      end
    end

    context "validations >" do
      it "is valid with or without an organization" do
        expect(build(:global_barcode_item, organization: nil)).to be_valid
        org = Organization.try(:first) || create(:organization)
        expect(build(:global_barcode_item, organization: org)).to be_valid
      end

      it "enforces uniqueness in the global scope" do
        barcode = create(:global_barcode_item, value: "DEADBEEF")
        expect(build(:global_barcode_item, value: barcode.value)).not_to be_valid
      end

      it "allows multiple barcodes to point at the same canonical item" do
        canonical_item = CanonicalItem.first
        create(:global_barcode_item, barcodeable: canonical_item)
        expect(build(:global_barcode_item, barcodeable: canonical_item)).to be_valid
      end

      include_examples "common barcode tests", :global_barcode_item
    end
  end

  context "Organization barcodes" do
    let(:item) { create(:item) }
    let(:barcode_item) { create(:barcode_item, barcodeable: item) }

    it "updates a counter in Item whenever it tracks a new barcode" do
      expect { barcode_item }.to change { item.barcode_count }.to(1)
    end

    # These are scopes that are expressly to integrate with Filterable
    context "filters >" do
      it "->item_id shows only barcodes for a specific item_id" do
        barcode_item
        create(:barcode_item)
        results = BarcodeItem.barcodeable_id(item.id)
        expect(results.length).to eq(1)
        expect(results.first).to eq(barcode_item)
      end
    end

    context "scopes >" do
      it "->for_csv_export will accept an organization and provide all barcodes for that org" do
        barcode_item
        create(:barcode_item, organization: create(:organization))
        results = BarcodeItem.for_csv_export(barcode_item.organization)
        expect(results.length).to eq(1)
        expect(results.first).to eq(barcode_item)
      end
      it "#by_item_partner_key returns barcodes that match the partner key" do
        i1 = create(:item, canonical_item: CanonicalItem.first)
        i2 = create(:item, canonical_item: CanonicalItem.last)
        b1 = create(:barcode_item, barcodeable: i1)
        create(:global_barcode_item, barcodeable: i2)
        expect(BarcodeItem.by_item_partner_key(i1.partner_key).first).to eq(b1)
      end
      it "->by_value returns the barcode with that value" do
        b1 = create(:global_barcode_item, value: "DEADBEEF")
        create(:global_barcode_item, value: "IDDQD")
        expect(BarcodeItem.by_value("DEADBEEF").first).to eq(b1)
      end
    end

    describe "combining global and organization barcodes" do
      it "shows both barcodes" do
        BarcodeItem.delete_all
        create(:global_barcode_item)
        create(:barcode_item, organization: @organization)
        expect(BarcodeItem.organization_barcodes_with_globals(@organization).count).to eq(2)
      end
    end

    context "when searching for a barcode where there is a global and local with the same value" do
      let!(:canonical_item) { create(:canonical_item, partner_key: "foo", name: "base item") }
      let!(:item) { create(:item, partner_key: "foo", name: "custom item", organization: @organization) }
      let!(:other_item) { create(:item, partner_key: "foo", name: "other item", organization: create(:organization, skip_items: true)) }

      let!(:global) { create(:global_barcode_item, value: "DEADBEEF", barcodeable: canonical_item) }
      let!(:local) { create(:barcode_item, value: "DEADBEEF", barcodeable: item, organization: @organization) }
      let!(:other_local) { create(:barcode_item, value: "DEADBEEF", barcodeable: other_item, organization: other_item.organization) }

      it "favors the local barcode" do
        search = BarcodeItem.find_by!(value: "DEADBEEF")
        expect(search).to eq(local)
      end
    end

    context "validations >" do
      it "is valid only with an organization" do
        expect(build(:barcode_item, organization: nil)).not_to be_valid
        org = Organization.try(:first) || create(:organization)
        expect(build(:barcode_item, organization: org)).to be_valid
      end

      it "does not enforces value uniqueness across organizations" do
        barcode = create(:barcode_item, value: "DEADBEEF", organization: @organization)
        expect(build(:barcode_item, value: barcode.value, organization: create(:organization, skip_items: true))).to be_valid
      end

      it "enforces value uniqueness within the organization" do
        barcode = create(:barcode_item, value: "DEADBEEF", organization: @organization)
        expect(build(:barcode_item, value: barcode.value, organization: @organization)).not_to be_valid
      end

      it "does not enforce value uniqueness compared with the global scope" do
        barcode = create(:global_barcode_item, value: "DEADBEEF")
        expect(build(:barcode_item, value: barcode.value, organization: @organization)).to be_valid
      end

      it "allows multiple barcodes to point at the same item" do
        item = create(:item, organization: @organization)
        create(:barcode_item, organization: @organization, barcodeable: item)
        expect(build(:barcode_item, organization: @organization, barcodeable: item)).to be_valid
      end

      include_examples "common barcode tests", :barcode_item
    end

    describe "to_h >" do
      it "emits a hash for a line_item" do
        expect(barcode_item.to_h).to eq(barcodeable_id: barcode_item.barcodeable_id, barcodeable_type: barcode_item.barcodeable_type, quantity: barcode_item.quantity)
      end
    end
  end
end
