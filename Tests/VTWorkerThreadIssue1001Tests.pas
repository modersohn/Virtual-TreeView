unit VTWorkerThreadIssue1001Tests;

interface

uses
  DUnitX.TestFramework,
  Classes,
  Vcl.Forms,
  VirtualTrees;

type
  TTestBaseVirtualTree = class(TBaseVirtualTree)
  public
    property OnCompareNodes;
  end;

  [TestFixture]
  TVTWorkerThreadIssue1001Tests = class
  strict private
    fTree: TTestBaseVirtualTree;
    fForm: TForm;
    fItemMeasured: Boolean;

    procedure TreeMeasureItem(Sender: TBaseVirtualTree; TargetCanvas: TCanvas;
      Node: PVirtualNode; var NodeHeight: Integer);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    /// Test for CheckSynchronize when tree is destroyed
    /// repeated because AVs are not realiable
    [Test, RepeatTestAttribute(200)]
    procedure TestDestroyWhileWorkerThreadBusy;
    [Test, RepeatTestAttribute(200)]
    procedure TestDestroyWhileWorkerThreadBusyVariableNodeHeight;
    [RepeatTestAttribute(200)]
    procedure TestDestroyWhileWorkerThreadBusyVariableNodeHeightExtended;
    [Test, RepeatTestAttribute(200)]
    procedure TestEndUpdateFromSecondaryThread;
  end;

implementation

uses
  VirtualTrees.WorkerThread,
  SysUtils;

procedure TVTWorkerThreadIssue1001Tests.Setup;
begin
  TThread.Synchronize(nil, procedure
    begin
      fForm := TForm.Create(nil);
      fTree := TTestBaseVirtualTree.Create(fForm);
      fTree.TreeOptions.AutoOptions:= fTree.TreeOptions.AutoOptions - [toAutoSort];
    end);
end;

procedure TVTWorkerThreadIssue1001Tests.TearDown;
begin
  TThread.Synchronize(nil, procedure
    begin
      FreeAndNil(fForm);
    end);
end;

procedure TVTWorkerThreadIssue1001Tests.TestDestroyWhileWorkerThreadBusy;
begin
  TThread.Synchronize(nil, procedure
    begin
      fTree.SetChildCount(fTree.RootNode, 10000);
      Assert.AreEqual(fTree.RootNode.ChildCount + 1, fTree.RootNode.TotalCount, 'TotalCount <> ChildCount + 1');
      FreeAndNil(fTree);
      FreeAndNil(fForm);

      //Now that the tree is destroyed, we have to ensure that the code called
      //from WorkerThread.Execute via Synchronize is executed and causes the AV.
      //In a real-world GUI Application, CheckSynchronize is called often, but
      //here in a Console application we have to do this ourselves.
      //Unfortunately the AV will not make the test fail, since it is raised
      //in WorkerThread, which has FreeOnTerminate = True; therefore the AVs
      //can only be seen with the debugger.
      CheckSynchronize;
    end);
end;

procedure TVTWorkerThreadIssue1001Tests.TestDestroyWhileWorkerThreadBusyVariableNodeHeight;
begin
  fTree.OnMeasureItem:= TreeMeasureItem;
  fTree.TreeOptions.AutoOptions:= fTree.TreeOptions.AutoOptions - [toAutoSort];
  fTree.TreeOptions.MiscOptions:= fTree.TreeOptions.MiscOptions + [toVariableNodeHeight];
  fTree.BeginUpdate;
  try
    fTree.SetChildCount(fTree.RootNode, CacheThreshold + 1);
  finally
    fTree.EndUpdate;
  end;
  FreeAndNil(fTree);
  FreeAndNil(fForm);

  //See if some code which might AV now is still scheduled
  CheckSynchronize;
end;

procedure TVTWorkerThreadIssue1001Tests.TestDestroyWhileWorkerThreadBusyVariableNodeHeightExtended;
var
  i: Integer;
begin
  fTree.OnMeasureItem:= TreeMeasureItem;
  fTree.TreeOptions.AutoOptions:= fTree.TreeOptions.AutoOptions - [toAutoSort];
  fTree.TreeOptions.MiscOptions:= fTree.TreeOptions.MiscOptions + [toVariableNodeHeight];
  fTree.BeginUpdate;
  try
    fTree.SetChildCount(fTree.RootNode, CacheThreshold + 1);

    fTree.ReinitNode(nil, True); //invalidate all nodes so EndUpdate will actually measure them again
  finally
    fTree.EndUpdate;
  end;
  //wait for validation to actually start
  while (tsValidationNeeded in fTree.TreeStates) do
  begin
    Sleep(1);
    CheckSynchronize;
  end;
  Assert.IsTrue(tsValidating in fTree.TreeStates, 'Tree not in tsValidating');

  fItemMeasured:= False;
  for i:= 1 to 10000 do
  begin
    CheckSynchronize;
    Sleep(1);
    if fItemMeasured then
      Break;
    Assert.IsTrue(tsValidating in fTree.TreeStates, 'Tree should not finish validation before an item was measured');
  end;
  Assert.IsTrue(fItemMeasured, 'no MeasureItem event was fired');
  FreeAndNil(fTree);
  FreeAndNil(fForm);

  //See if some code which might AV now is still scheduled
  CheckSynchronize;
end;

procedure TVTWorkerThreadIssue1001Tests.TestEndUpdateFromSecondaryThread;
begin
  Assert.AreEqual(MainThreadID, TThread.CurrentThread.ThreadID, 'Test must be run from MainThread');

  fTree.SetChildCount(fTree.RootNode, 10000);

  TThread.CreateAnonymousThread(procedure
    begin
      TThread.Synchronize(nil, procedure
        begin
          fTree.InterruptValidation;
        end)
    end).Start;

  fTree.InterruptValidation;
end;

procedure TVTWorkerThreadIssue1001Tests.TreeMeasureItem(
  Sender: TBaseVirtualTree; TargetCanvas: TCanvas; Node: PVirtualNode;
  var NodeHeight: Integer);
begin
  NodeHeight:= 18 + Random(10);
  fItemMeasured:= True;
end;

initialization
  Randomize;
  TDUnitX.RegisterTestFixture(TVTWorkerThreadIssue1001Tests);
end.
