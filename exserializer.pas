unit exSerializer;

interface

uses
  Classes, SysUtils, DB, StrUtils, Variants, {$IFDEF FPC}fgl, {$ELSE} Generics.Collections, {$ENDIF}
  exClasses, exDefinition, exExporter;

type
  TexExporterAccess = class(TexExporter);

  { TexBaseSerializer }

  TexBaseSerializer = class(TexSerializer)
  protected
    procedure DoWork;
    procedure DoSerializeData(APackage: TexPackage; AData: WideString);
    function FindData(ASession: TexSession; AResultMap: TexResutMap): TStrings;
    function ExtractColumnValue(AColumn: TexColumn; ADataSet: TDataSet): String;
    function BeforeSerialize(AData: String; ASession: TexSession): String;
  end;

  { TexColumnSerializer }

  TexColumnSerializer = class(TexBaseSerializer)
  private
    FDelimiter: String;
  public
    procedure Serialize(ASessions: TexSessionList; AMaster: TDataSet; AResult: TexResutMap); override;
  published
    property Delimiter: String read FDelimiter write FDelimiter;
  end;

  { TexHierarchicalSerializer }

  TexHierarchicalSerializer = class(TexBaseSerializer)
  protected
    function FormatData(ASession: TexSession; AMaster: TDataSet): String; virtual; abstract;
  public
    procedure Serialize(ASessions: TexSessionList; AMaster: TDataSet; AResult: TexResutMap); override;
  end;

  { TexJsonSerializer }

  TexJsonSerializer = class(TexHierarchicalSerializer)
  private
    FHideRootKeys: Boolean;
  protected
    function FormatData(ASession: TexSession; AMaster: TDataSet): String; override;
  published
    property HideRootKeys: Boolean read FHideRootKeys write FHideRootKeys default False;
  end;

  { TexXmlSerializer }

  TexXmlSerializer = class(TexHierarchicalSerializer)
  private
    FEncoding: String;
    FItemTag: String;
    FVersion: String;
  private
    function EncodeTag(AName, AValue: String): String;
  protected
    function FormatData(ASession: TexSession; AMaster: TDataSet): String; override;
  public
    constructor Create(AExporter: TexExporter); override;
    procedure Serialize(ASessions: TexSessionList; AMaster: TDataSet; AResult: TexResutMap); override;
  published
    property Version: String read FVersion write FVersion;
    property Encoding: String read FEncoding write FEncoding;
    property ItemTag: String read FItemTag write FItemTag;
  end;

const
  sexSColumnSerializer = 'Column';
  sexSJsonSerializer = 'JSON';
  sexSXMLSerializer = 'XML';

var
  FRegisteredSerializers: TexRegisteredClasses;

function GetRegisteredSerializers: TexRegisteredClasses;

implementation

function GetRegisteredSerializers: TexRegisteredClasses;
begin
  if FRegisteredSerializers = nil then
    FRegisteredSerializers := TexRegisteredClasses.Create;
  Result := FRegisteredSerializers;
end;

{ TexBaseSerializer }

procedure TexBaseSerializer.DoSerializeData(APackage: TexPackage; AData: WideString);
begin
  try
    if (Assigned(OnSerializeData)) then
      OnSerializeData(APackage, AData);
  finally
    TexExporterAccess(Exporter).FObjectCounter := 0;
  end;
end;

procedure TexBaseSerializer.DoWork;
begin
  if (Assigned(OnWork)) then
    OnWork(Exporter);
end;

function TexBaseSerializer.FindData(ASession: TexSession; AResultMap: TexResutMap): TStrings;
var
  APackage: TexPackage;
  AOwner: TexSession;
  ASessionName: String;
begin
  AOwner := TexSessionList(ASession.Collection).GetOwner as TexSession;

  if(AOwner <> nil) then
    ASessionName := AOwner.Name
  else
    ASessionName := ASession.Name;

  APackage := Exporter.Packages.FindBySession(ASessionName);
  if (APackage = nil) and (AOwner = nil) then
     raise Exception.CreateFmt('The session "%s" does not have a file associated', [ASession.Name])
  else begin
    {$IFDEF FPC}
    if (AResultMap.IndexOf(APackage.Name) <> -1) then
    {$ELSE}
    if (AResultMap.ContainsKey(APackage.Name)) then
    {$ENDIF}
      Result := AResultMap[APackage.Name]
    else begin
      Result := TStringList.Create;
      AResultMap.Add(APackage.Name, Result);
    end;
  end;
end;

function TexBaseSerializer.ExtractColumnValue(AColumn: TexColumn; ADataSet: TDataSet): String;
var
  ASize: Integer;
  AComplete: Char;
  AExpression: String;
  AAlign: TexAlignment;
  AField: TField;
  ADictionary: TexDictionary;
  AArgs: TexScriptArgs;
  AValue: Variant;
begin
  AValue := Null;
  AField := ADataSet.FindField(AColumn.Name);

  AComplete := AColumn.Complete;
  ASize := AColumn.Size;
  AAlign := AColumn.Align;
  AExpression := AColumn.Expression;

  if (AField <> nil) then
  begin
    Result := AField.AsString;
    AValue := AField.Value;
  end;

  if (AColumn.Dictionary <> '') then
  begin
    ADictionary := Exporter.Dictionaries.FindByName(AColumn.Dictionary);
    if (ADictionary <> nil) then
    begin
      if (AComplete = VK_CHAR_SPACE) then
        AComplete := ADictionary.Complete;

      if (ASize = 0) then
        ASize := ADictionary.Size;

      if (AAlign = altNone) then
         AAlign := ADictionary.Align;

      if (AExpression = '') then
         AExpression := ADictionary.Expression;
    end;
  end;

  if (AExpression <> '') then
  begin
    AArgs := TexScriptArgs.Create;
    try
      {$IFDEF FPC}
      AArgs['value'] := AValue;
      {$ELSE}
      AArgs.AddOrSetValue('value', AValue);
      {$ENDIF}
      Result := Exporter.ExecuteExpression(AExpression, AArgs);
    finally
      AArgs.Free;
    end;
  end;

  if (ASize <> 0) then
  begin
    if (ASize < Length(Result)) then
       Result := Copy(Result, 1, ASize)
    else begin
      case AAlign of
        altLeft, altNone:
          Result := {$IFDEF FPC}AddCharR(AComplete, Result, ASize){$ELSE} Result.PadRight(ASize, AComplete){$ENDIF};
        altRight:
          Result := {$IFDEF FPC}AddChar(AComplete, Result, ASize){$ELSE} Result.PadLeft(ASize, AComplete){$ENDIF};
      end;
    end;
  end;
end;

function TexBaseSerializer.BeforeSerialize(AData: String; ASession: TexSession): String;
var
  AArgs: TexScriptArgs;
  AEventResult: Variant;
begin
  AArgs := TexScriptArgs.Create;
  try
    {$IFDEF FPC}
    AArgs['Value'] := AData;
    {$ELSE}
    AArgs.AddOrSetValue('Value', AData);
    {$ENDIF}
    AEventResult := Exporter.ExecuteEvent(EXPORTER_BEFORE_SERIALIZE, AArgs);
    if (AEventResult <> Unassigned) then
      Result := AEventResult
    else
      Result := AData;
  finally
    AArgs.Free;
  end;
end;

{ TexColumnSerializer }

procedure TexColumnSerializer.Serialize(ASessions: TexSessionList; AMaster: TDataSet; AResult: TexResutMap);
var
  I, J,
  ALength: Integer;
  ARow,
  AValue: String;
  AData: TStrings;
  AQuery: TDataSet;
  ASession: TexSession;
  APipeline: TexPipeline;
begin
  for I := 0 to ASessions.Count -1 do
  begin
    ASession := ASessions[I];
    if (ASession.Visible) then
    begin
      AData := FindData(ASession, AResult);
      APipeline := Exporter.Pipelines.FindByName(ASession.Pipeline);
      AQuery := Exporter.Provider.CreateQuery(APipeline.SQL.Text, AMaster);
      try
        AQuery.Open;
        while (not AQuery.EOF) do
        begin
          ARow := '';
          Exporter.CurrentDataSet := AQuery;

          for J := 0 to ASession.Columns.Count -1 do
          begin
            AValue := ExtractColumnValue(ASession.Columns[J], AQuery);
            ARow := ARow + AValue + FDelimiter;
          end;

          ALength := Length(ARow);
          if (FDelimiter <> '') and (ALength > 0) then
             Delete(ARow, ALength, 1);

          ARow := BeforeSerialize(ARow, ASession);
          AData.Add(ARow);
          Serialize(ASession.Sessions, AQuery, AResult);

          if (ASessions.Owner = nil) then
            DoWork;

          AQuery.Next;
        end;
      finally
        AQuery.Free;
      end;
    end;
  end;
end;

{ TexHierarchicalSerializer }

procedure TexHierarchicalSerializer.Serialize(ASessions: TexSessionList; AMaster: TDataSet; AResult: TexResutMap);
var
  I: Integer;
  AData: TStrings;
  ASession: TexSession;
begin
  for I := 0 to ASessions.Count - 1 do
  begin
    ASession := ASessions[I];
    AData := FindData(ASession, AResult);
    AData.Add(FormatData(ASession, AMaster));

    if (ASessions.Owner = nil) then
      DoWork;
  end;
end;

{ TexJsonSerializer }

function TexJsonSerializer.FormatData(ASession: TexSession; AMaster: TDataSet): String;
var
  I, J: Integer;
  AJson,
  AAlias,
  AValue: String;
  ASame: Boolean;
  AQuery: TDataSet;
  AOwner: TexSession;
  AColumn: TexColumn;
  APipeline: TexPipeline;
  AElements: TStringList;
  APackage: TexPackage;
begin
  Result := '';
  AElements := TStringList.Create;
  try
    AOwner := ASession.Collection.Owner as TexSession;
    APipeline := Exporter.Pipelines.FindByName(ASession.Pipeline);
    ASame := (AOwner <> nil) and (SameText(ASession.Pipeline, AOwner.Pipeline));

    if (ASame) then
      AQuery := AMaster
    else
      AQuery := Exporter.Provider.CreateQuery(APipeline.SQL.Text, AMaster);

    try
      AQuery.Open;
      while (not AQuery.EOF) do
      begin
        AJson := '';
        Exporter.CurrentDataSet := AQuery;

        for J := 0 to ASession.Columns.Count -1 do
        begin
          AColumn := ASession.Columns[J];
          AValue := ExtractColumnValue(AColumn, AQuery);
          AAlias := IfThen(Trim(AColumn.Alias) <> '', AColumn.Alias, AColumn.Name);
          AJson := AJson + Format('"%s":"%s"', [AAlias, AValue]) + ',';
        end;

        for I := 0 to ASession.Sessions.Count - 1 do
          AJson := AJson + FormatData(ASession.Sessions[I], AQuery) + ',';

        Delete(AJson, Length(AJson), 1);
        AJson := Format('{%s}', [AJson]);
        AElements.Add(AJson);

        if (ASame) then
          Break;

        if (AOwner = nil) then
        begin
          APackage := Exporter.Packages.FindBySession(ASession.Name);
          DoSerializeData(APackage, AJson);
        end;

        AQuery.Next;
      end;

      Result := '';
      for J := 0 to AElements.Count -1 do
        Result := Result + AElements[J] + ',';

      Delete(Result, Length(Result), 1);

      if (not ASame) then
        Result := Format('[%s]', [Result]);

      if (AOwner <> nil) then
        Result := Format('"%s":%s', [ASession.Name, Result])
      else if (not Self.HideRootKeys) then
        Result := Format('{"%s":%s}', [ASession.Name, Result]);
    finally
      if (not ASame) then
        AQuery.Free;
    end;
  finally
    AElements.Free;
  end;
end;

{ TexXmlSerializer }

constructor TexXmlSerializer.Create(AExporter: TexExporter);
begin
  inherited Create(AExporter);
  FVersion := '1.0';
  FEncoding := 'UTF-8';
  FItemTag := 'item';
end;

procedure TexXmlSerializer.Serialize(ASessions: TexSessionList; AMaster: TDataSet; AResult: TexResutMap);
var
  {$IFDEF FPC}
  I: Integer;
  {$ENDIF}
  AData: TStrings;
  AKey: String;
begin
  inherited Serialize(ASessions, AMaster, AResult);
  {$IFDEF FPC}
  for I := 0 to AResult.Count -1 do
  begin
    AKey := AResult.Keys[I];
  {$ELSE}
  for AKey in AResult.Keys do
  begin
  {$ENDIF}
    AData := AResult[AKey];
    AData.Insert(0, Format('<?xml version="%s" encoding="%s"?>', [FVersion, FEncoding]));
  end;
end;

function TexXmlSerializer.EncodeTag(AName, AValue: String): String;
begin
  Result := Format('<%s>%s</%s>', [AName, AValue, AName]);
end;

function TexXmlSerializer.FormatData(ASession: TexSession; AMaster: TDataSet): String;
var
  I, J: Integer;
  AXml,
  AAlias,
  AValue: String;
  ASame: Boolean;
  AQuery: TDataSet;
  AOwner: TexSession;
  AColumn: TexColumn;
  APipeline: TexPipeline;
  APackage: TexPackage;
begin
  Result := '';
  AOwner := ASession.Collection.Owner as TexSession;
  APipeline := Exporter.Pipelines.FindByName(ASession.Pipeline);
  ASame := (AOwner <> nil) and (SameText(ASession.Pipeline, AOwner.Pipeline));

  if (ASame) then
    AQuery := AMaster
  else
    AQuery := Exporter.Provider.CreateQuery(APipeline.SQL.Text, AMaster);

  try
    AQuery.Open;
    while (not AQuery.EOF) do
    begin
      AXml := '';
      Exporter.CurrentDataSet := AQuery;

      for J := 0 to ASession.Columns.Count -1 do
      begin
        AColumn := ASession.Columns[J];
        AAlias := IfThen(Trim(AColumn.Alias) <> '', AColumn.Alias, AColumn.Name);
        AValue := ExtractColumnValue(AColumn, AQuery);
        AXml := AXml + EncodeTag(AAlias, AValue);
      end;

      for I := 0 to ASession.Sessions.Count - 1 do
        AXml := AXml + FormatData(ASession.Sessions[I], AQuery);

      if (not ASame) then
        AXml := EncodeTag(FItemTag, AXml)
      else begin
        Result := Result + AXml;
        Break;
      end;

      Result := Result + AXml;

      if (AOwner = nil) then
      begin
        APackage := Exporter.Packages.FindBySession(ASession.Name);
        DoSerializeData(APackage, Result);
      end;

      AQuery.Next;
    end;
    Result := EncodeTag(ASession.Name, Result);
  finally
    if (not ASame) then
      AQuery.Free;
  end;
end;


initialization
  GetRegisteredSerializers.RegisterClass(sexSColumnSerializer, TexColumnSerializer);
  GetRegisteredSerializers.RegisterClass(sexSJsonSerializer, TexJsonSerializer);
  GetRegisteredSerializers.RegisterClass(sexSXMLSerializer, TexXmlSerializer);

end.

