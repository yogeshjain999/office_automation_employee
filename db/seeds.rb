# Retreive array of ROLES (Constant) from Role model and add roles in database
OfficeAutomationEmployee::Role::ROLES.each do |role|
  OfficeAutomationEmployee::Role.find_or_create_by(name: role)
end