class ChangeLastModifiedColumnsToDatetime < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL
      ALTER TABLE characters
        ALTER COLUMN equipment_last_modified TYPE timestamp
          USING equipment_last_modified::timestamp,
        ALTER COLUMN talents_last_modified TYPE timestamp
          USING talents_last_modified::timestamp
    SQL
  end

  def down
    execute <<~SQL
      ALTER TABLE characters
        ALTER COLUMN equipment_last_modified TYPE varchar
          USING TO_CHAR(equipment_last_modified AT TIME ZONE 'UTC', 'Dy, DD Mon YYYY HH24:MI:SS "GMT"'),
        ALTER COLUMN talents_last_modified TYPE varchar
          USING TO_CHAR(talents_last_modified AT TIME ZONE 'UTC', 'Dy, DD Mon YYYY HH24:MI:SS "GMT"')
    SQL
  end
end