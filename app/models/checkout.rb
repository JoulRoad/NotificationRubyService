class Checkout
  def self.determine_has_user_ordered ruid,uuid
    ruidOrdered = nil
    uuidOrdered = nil
    uuidOrdered = $as_userDatabase.get(key: uuid, setname: "user_flags", bins: "has_ordered") if uuid.present?
    return uuidOrdered, "uuid" if uuidOrdered
    ruidOrdered = $as_userDatabase.get(key: ruid, setname: "user_flags", bins: "has_ordered") if ruid.present?
    return ruidOrdered, "ruid"
  end

end