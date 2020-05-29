# frozen_string_literal: true

# Cannon Mallory
# malloc3@uw.edu
#
# Module for working with collections
# These actions should involve the WHOLE plate not individual wells.
# NOTE: The collection is doing the whole action

needs 'Standard Libs/ItemActions'

module CollectionActions
  include ItemActions

  # Creates new collection.  Instructions to tech optional
  #
  # @param c_type [String] the collection type
  # @param label_plate [Boolean] instructs tech to label if true
  # @return working_plate [Collection]
  def make_new_plate(c_type, label_plate: true)
    working_plate = Collection.new_collection(c_type)
    get_and_label_new_plate(working_plate) if label_plate
    working_plate
  end

  # Makes the required number of collections and populates with samples
  # returns an array of of collections created
  #
  # @param samples [Array<FieldValue>] or [Array<Samples>]
  # @param collection_type [String] the type of collection that is to be made
  # @param first_collection [Collection] optional a collection to start with
  # @param add_column_wise [Boolean] default false add samples by column
  # @param label_plates [Boolean] default false, provides instructions
  # @return [Array<Collection>] array of collections created
  def make_and_populate_collection(samples, collection_type: nil,
                                   first_collection: nil,
                                   add_column_wise: false,
                                   label_plates: false)

    if collection_type.nil? && first_collection.nil?
      ProtocolError 'Either collection_type or first_collection must be given'
    end

    unless collection_type.nil? || first_collection.nil?
      ProtocolError 'Both collection_type and first_collection cannot be given'
    end

    capacity = nil
    if collection_type.nil?
      collection_type = fisrt_collection.object_type.name
      capacity = first_collection.capacity
      remaining_space = first_collection.get_empty.length
      add_samples_to_collection(samples[0...remaining_space - 1],
                                first_collection,
                                label_plates: label_plates,
                                add_column_wise: add_column_wise)
      samples = samples.drop(remaining_space)
    else
      obj_type = ObjectType.find_by_name(collection_type)
      capacity = obj_type.columns * obj_type.rows
    end

    collections = []
    collections.push(first_collection) unless first_collection.nil?
    grouped_samples = samples.in_groups_of(capacity, false)
    grouped_samples.each do |sub_samples|
      collection = make_new_plate(collection_type, label_plate: label_plates)
      add_samples_to_collection(sub_samples, collection, 
                                add_column_wise: add_column_wise)
      collections.push(collection)
    end
    collections
  end

  # Assigns samples to specific well locations
  #
  # @param samples [Array<FieldValue>] or [Array<Samples>]
  # @param to_collection [Collection]
  # @param add_row_wise [Boolean] default false, will add samples by column
  # @raise if not enough space in collection
  def add_samples_to_collection(samples, to_collection, add_column_wise: false)
    samples.map! do |fv|
      unless fv.is_a?(Sample)
        fv = fv.sample
      end
      fv
    end

    slots_left = to_collection.get_empty.length
    raise 'Not enough space in in collection' if samples.length > slots_left

    if add_column_wise
      add_samples_column_wise(samples, to_collection)
    else
      to_collection.add_samples(samples)
    end
    to_collection
  end

  # Adds samples to the first slot in the first available column
  # as opposed to column wise that the base version does.
  #
  # @param samples_to_add [Array<Samples>] an array of samples
  # @param collection [Collection] the collection to include samples
  def add_samples_column_wise(samples_to_add, collection)
    col_matrix = collection.matrix
    columns = col_matrix.first.size
    rows = col_matrix.size
    samples_to_add.each do |sample|
      break_pattern = false
      columns.times do |col|
        rows.times do |row|
          if collection.part(row, col).nil?
            collection.set(row, col, sample)
            break_pattern = true
            break
          end
        end
        break if break_pattern
      end
    end
  end

  # Instructions on getting and labeling new plate
  #
  # @param plate [Collection] the plate to be retrieved and labeled
  def get_and_label_new_plate(plate)
    show do
      title 'Get and Label Working Plate'
      note "Get a <b>#{plate.object_type.name}</b> and
           label it ID: <b>#{plate.id}</b>"
    end
  end

  # Associates field_values to corresponding samples in a collection
  # TODO not sure multiples of samples is handled in the best way...
  #
  # @param field_values [Array<Field Values>] array of field values
  # @param collection [Collection] the destination collection
  # replaced make_output_plate
  def associate_field_values_to_plate(field_values, collection)
    already_associated_parts = []
    field_values.each do |fv|
      r_c = nil
      collection.find(fv.sample).each do |loc|
        r_c = loc
        break unless already_associated_parts.include?(loc)
      end
      r_c = collection.find(fv.sample).first
      unless r_c.nil?
        fv.set(collection: collection, row: r_c[0], column: r_c[1])
      end
    end
  end
end
