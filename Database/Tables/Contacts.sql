﻿CREATE TABLE [dbo].[Contacts]
(
  [Id] INT NOT NULL PRIMARY KEY IDENTITY, 
    [Name] NVARCHAR(50) NOT NULL, 
    [LastName] NVARCHAR(50) NOT NULL, 
    [Email] VARCHAR(50) NULL, 
    [Phone] VARCHAR(15) NULL
)
