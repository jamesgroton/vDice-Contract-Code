pragma solidity ^0.4.18;

contract StorageData {
  string data;

  function StorageData(string _data) public {
    data = _data;
  }

  function getData() constant public returns (string) {
    return data;
  }

  function setData(string _data) public returns (string) {
    data = _data;
    return data;
  }
}
