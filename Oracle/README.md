# Oracle Script to find local accounts in Oracle Servers in Windows Environtmens
Pre-requisites
Oracle account in SS as a secret
API username and password. API user should have view permission on that secret
Oracle Driver should be installed on SS or DE server.
Domain User to invoke PS script
PSRemoting should be enabled.
the server that PS run should have access to SS URL. 

Use Cases
You have a lot of Oracle Servers and DBS. Each Server has more than 1 DB. You need to know the local accounts on each DB. You have the same naming condition on all DB.
